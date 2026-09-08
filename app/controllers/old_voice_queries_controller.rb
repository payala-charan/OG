# app/controllers/voice_queries_controller.rb
class VoiceQueriesController < ApplicationController
  def create
    debugger
    user_text = (params[:text] || params[:query] || params.dig(:voice_query, :text)).to_s.strip
    raise ArgumentError, "text param required" if user_text.blank?

    Rails.logger.info("[VoiceQuery] user_text=#{user_text.inspect}")

    # 1) Try LLM intent extraction (may return a Hash or string-containing-json)
    raw_llm = safe_call { LlmService.extract_intent(user_text) }
    llm_result = normalize_intent_result(raw_llm)
    Rails.logger.info("[VoiceQuery] llm_result=#{llm_result.inspect}")
    # If LLM gave a clear non-db intent (greeting/exit/general_knowledge) handle it
    if non_db_intent?(llm_result)
      return render json: handle_non_db_intent(llm_result)
    end
    # If LLM is reliable for DB queries, handle it
    if intent_reliable?(llm_result)
      Rails.logger.info("[VoiceQuery] using LLM result for DB")
      return handle_db_intent(llm_result, user_text)
    end
    # 2) NLP rule-based attempt
    raw_nlp = safe_call { NlpService.extract_intent(user_text) }
    nlp_result = normalize_intent_result(raw_nlp)
    Rails.logger.info("[VoiceQuery] nlp_result=#{nlp_result.inspect}")

    if non_db_intent?(nlp_result)
      return render json: handle_non_db_intent(nlp_result)
    end

    if intent_reliable?(nlp_result)
      Rails.logger.info("[VoiceQuery] using NLP result for DB")
      return handle_db_intent(nlp_result, user_text)
    end

    # 3) Regex-based attempt
    raw_regex = safe_call { RegexFallbackService.extract_intent(user_text) }
    regex_result = normalize_intent_result(raw_regex)
    Rails.logger.info("[VoiceQuery] regex_result=#{regex_result.inspect}")

    if non_db_intent?(regex_result)
      return render json: handle_non_db_intent(regex_result)
    end

    if intent_reliable?(regex_result)
      Rails.logger.info("[VoiceQuery] using Regex result for DB")
      return handle_db_intent(regex_result, user_text)
    end

    # 4) Last ditch: search values across schema (trigram-backed)
    generic = GenericResolver.new
    results = safe_call { generic.find_by_value(user_text) } || {}
    if results.present?
      Rails.logger.info("[VoiceQuery] fallback: generic.find_by_value returned hits")
      return render json: { type: "search_results", results: compact_results(results), source: "trigram_fallback" }
    end

    # Nothing matched
    Rails.logger.info("[VoiceQuery] no match for text; returning unknown")
    render json: { intent: "unknown", message: "I couldn't understand this as a DB query. Try: 'show students where branch is CSE'." }, status: 200
  rescue => e
    Rails.logger.error("[VoiceQuery] ERROR #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    render json: { error: e.message }, status: 500
  end

  private

  # Safe caller: prevents exceptions inside services from propagating up
  def safe_call
    yield
  rescue => e
    Rails.logger.warn("[VoiceQuery] safe_call rescued: #{e.class}: #{e.message}")
    nil
  end

  # Normalize LLM/NLP/Regex output:
  # Accepts Hash, or String that contains JSON, or raw string; returns a Hash with string keys.
  def normalize_intent_result(raw)
    return {} if raw.nil?

    # If it's already a Hash with string keys, return a deep-stringified copy
    if raw.is_a?(Hash)
      return stringify_keys_recursive(raw)
    end

    # If it's a string that looks like JSON (maybe inside markdown code fences), try to extract and parse
    if raw.is_a?(String)
      # Remove markdown fences ```json ... ```
      cleaned = raw.gsub(/```(?:json)?/, "").strip

      # try to find JSON substring in the string
      json_candidate = nil
      begin
        # if entire cleaned string is JSON
        json_candidate = JSON.parse(cleaned) rescue nil
      rescue
        json_candidate = nil
      end

      unless json_candidate
        # try to extract first {...} or [ ... ] occurrence
        if m = cleaned.match(/(\{.*\}|\[.*\])/m)
          raw_json = m[1]
          json_candidate = JSON.parse(raw_json) rescue nil
        end
      end

      return stringify_keys_recursive(json_candidate) if json_candidate.is_a?(Hash)
      # fallback: return raw string in "raw" key so controller can interpret it
      return { "intent" => "unknown", "raw" => cleaned, "confidence" => 0.0 }
    end

    # unknown type: convert to string
    { "intent" => "unknown", "raw" => raw.to_s, "confidence" => 0.0 }
  end

  def stringify_keys_recursive(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_recursive(v) }
    when Array
      obj.map { |el| stringify_keys_recursive(el) }
    else
      obj
    end
  end

  # Return true if the intent is a non-DB user intent
  def non_db_intent?(intent_json)
    return false unless intent_json.is_a?(Hash)
    intent = intent_json["intent"].to_s
    %w[greeting exit general_knowledge unknown].include?(intent)
  end

  # Handles greeting/exit/general_knowledge/unknown with polite responses
  def handle_non_db_intent(intent_json)
    intent = intent_json["intent"].to_s
    case intent
    when "greeting"
      { reply: "Hello! 👋 How can I help you today? You can say things like: 'show payors', 'find students with cgpa above 8'." }
    when "exit"
      { reply: "Goodbye — feel free to ask again anytime!" }
    when "general_knowledge"
      { reply: "This looks like a general question. Would you like me to search the web or handle it differently?" }
    when "unknown"
      # If the LLM gave a raw JSON with intent greeting inside "raw", try to parse it again
      raw = intent_json["raw"]
      if raw.present? && raw.to_s.match?(/greeting/i)
        return { reply: "Hello! 👋 How can I help?" }
      end
      { reply: "I couldn't interpret that. Try: 'show payors' or 'give me students where branch is CSE'." }
    else
      { reply: "I couldn't interpret that. Try asking to 'show', 'display', or 'find' something." }
    end
  end

  # A more robust 'reliability' test - treat intents with >= 0.6 OR those that have explicit table/filters
  def intent_reliable?(intent_json)
    return false unless intent_json.is_a?(Hash)
    # if it contains known DB-intents explicitly, consider it reliable (even without confidence)
    if intent_json["intent"].present? && %w[select_filtered select_all select_record].include?(intent_json["intent"])
      return true
    end

    confidence = intent_json["confidence"].to_f
    return true if confidence >= 0.6

    # if table present and looks like a schema table, accept it (even low confidence)
    if intent_json["table"].present?
      t = intent_json["table"].to_s.downcase
      normalized = LlmService.normalize_table_name(t) rescue t
      return true if SchemaService.schema_map.key?(normalized.to_sym)
    end

    false
  end

  # Handle DB-intents (select_filtered, select_all, select_record)
  # This method renders JSON and returns.
  def handle_db_intent(intent_json, user_text)
    intent = intent_json["intent"].to_s
    Rails.logger.info("[VoiceQuery] handle_db_intent intent=#{intent.inspect}, intent_json=#{intent_json.inspect}")

    # If the intent is "select_record" and has an entity, perform a value search
    if intent == "select_record" && intent_json["entity"].present?
      results = GenericResolver.new.find_by_value(intent_json["entity"])
      if results.present?
        return render json: { type: "search_results", results: compact_results(results), source: "select_record_value_search" }
      else
        return render json: { message: "No records found for '#{intent_json["entity"]}'." }
      end
    end

    # Ground the table (intent might contain table as "payors" or symbol; normalize it)
    table_raw = intent_json["table"].presence || guess_table_from_text(user_text)
    table_sym = LlmService.normalize_table_name(table_raw).to_sym rescue nil if table_raw.present?

    # If still blank and filters exist, try to infer table from filters
    if table_sym.blank? && intent_json["filters"].present?
      candidate_tables = candidate_tables_for_filters(intent_json["filters"])
      table_sym = candidate_tables.first if candidate_tables.one?
    end

    # If it's a greeting/exit/general_knowledge (edge case), handle above
    if table_sym.blank?
      Rails.logger.info("[VoiceQuery] handle_db_intent: couldn't determine table. intent_json=#{intent_json.inspect}")
      return render json: { message: "Couldn't determine which table to query. Please mention the table (e.g., students, payors)." }
    end

    unless SchemaService.schema_map.key?(table_sym)
      Rails.logger.info("[VoiceQuery] handle_db_intent: unknown table=#{table_sym}. Known=#{SchemaService.schema_map.keys.inspect}")
      return render json: { message: "Unknown table #{table_sym}. Possible tables: #{SchemaService.schema_map.keys.join(', ')}" }
    end

    # Build and run query
    builder = ActiveRecordQueryBuilder.new(SchemaService.schema_map)
    records = builder.build_and_run(table_sym, intent_json["filters"] || [], select_cols: intent_json["columns"], limit: intent_json["limit"] || 200)

    render json: { type: "query_results", table: table_sym, count: records.count, data: records.as_json, source: "db_query" }
  end

  # Try to guess table name directly from text when LLM didn't provide it
  def guess_table_from_text(text)
    return nil if text.blank?
    tc = text.to_s.downcase
    SchemaService.schema_map.keys.each do |k|
      return k.to_s if tc.include?(k.to_s)
    end
    nil
  end

  def candidate_tables_for_filters(filters)
    candidates = []
    Array(filters).each do |f|
      col = f["column"].to_s
      SchemaService.models_with_column(col).each do |m|
        candidates << m.name.downcase.to_sym
      end
    end
    candidates.uniq
  end

  def compact_results(results)
    # results: { table_sym => ActiveRecord::Relation }
    results.transform_values do |rows|
      cols = rows.first&.attributes&.keys
      rows.limit(20).as_json(only: cols)
    end
  end
end








# app/controllers/voice_queries_controller.rb
class VoiceQueriesController < ApplicationController
  # POST /voice_queries/create
  # params: { text: "..." } or { query: "..." } or nested under :voice_query
  def create
    user_text = (params[:text] || params[:query] || params.dig(:voice_query, :text)).to_s.strip
    raise ArgumentError, "text param required" if user_text.blank?

    Rails.logger.info("[VoiceQuery] user_text=#{user_text.inspect}")

    # 1) Try LLM (may return Hash or String)
    raw_llm = safe_call { LlmService.extract_intent(user_text) }
    llm_result = normalize_intent_result(raw_llm)
    Rails.logger.info("[VoiceQuery] llm_result=#{llm_result.inspect}")

    # If LLM returned a clear non-DB intent (greeting, exit, general_knowledge), handle it immediately
    if non_db_intent?(llm_result)
      return render json: handle_non_db_intent(llm_result)
    end

    # If LLM looks reliable for DB query, use it
    if intent_reliable?(llm_result) && db_intent?(llm_result["intent"])
      Rails.logger.info("[VoiceQuery] using LLM for DB query")
      return handle_db_intent(llm_result, user_text)
    end

    # 2) NLP rule-based attempt
    raw_nlp = safe_call { NlpService.extract_intent(user_text) }
    nlp_result = normalize_intent_result(raw_nlp)
    Rails.logger.info("[VoiceQuery] nlp_result=#{nlp_result.inspect}")

    if non_db_intent?(nlp_result)
      return render json: handle_non_db_intent(nlp_result)
    end

    if intent_reliable?(nlp_result) && db_intent?(nlp_result["intent"])
      Rails.logger.info("[VoiceQuery] using NLP for DB query")
      return handle_db_intent(nlp_result, user_text)
    end

    # 3) Regex fallback
    raw_regex = safe_call { RegexFallbackService.extract_intent(user_text) }
    regex_result = normalize_intent_result(raw_regex)
    Rails.logger.info("[VoiceQuery] regex_result=#{regex_result.inspect}")

    if non_db_intent?(regex_result)
      return render json: handle_non_db_intent(regex_result)
    end

    if intent_reliable?(regex_result) && db_intent?(regex_result["intent"])
      Rails.logger.info("[VoiceQuery] using Regex for DB query")
      return handle_db_intent(regex_result, user_text)
    end

    # 4) Final fallback: full-text search across schema (trigram-backed)
    generic = GenericResolver.new
    results = safe_call { generic.find_by_value(user_text) } || {}
    if results.present?
      Rails.logger.info("[VoiceQuery] fallback: generic.find_by_value hits")
      return render json: { type: "search_results", results: compact_results(results), source: "trigram_fallback" }
    end

    Rails.logger.info("[VoiceQuery] no match for text; returning unknown")
    render json: { intent: "unknown", message: "I couldn't understand this as a DB query. Try: 'show students where branch is CSE'." }, status: 200
  rescue => e
    Rails.logger.error("[VoiceQuery] ERROR #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    render json: { error: e.message }, status: 500
  end

  private

  # Safe caller to protect controller flow
  def safe_call
    yield
  rescue => e
    Rails.logger.warn("[VoiceQuery] safe_call rescued: #{e.class}: #{e.message}")
    nil
  end

  # Turn various service outputs into a normalized Hash with string keys
  def normalize_intent_result(raw)
    return {} if raw.nil?

    # already a Hash
    if raw.is_a?(Hash)
      return stringify_keys_recursive(raw)
    end

    # If string: try to clean code fences, unescape, and parse JSON heuristically
    if raw.is_a?(String)
      cleaned = raw.dup
      cleaned.gsub!(/^\s*```(?:json)?\s*/i, '')
      cleaned.gsub!(/\s*```\s*$/i, '')
      cleaned.gsub!(/`([^`]*)`/, '\1')
      cleaned.gsub!(/\\n/, "\n")
      cleaned.gsub!(/\\\"/, '"')
      cleaned.strip!

      # Try to parse full JSON
      begin
        parsed = JSON.parse(cleaned)
        return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
      rescue JSON::ParserError
        # continue
      end

      # Try to extract first JSON object/array
      if m = cleaned.match(/(\{.*?\}|\[.*?\])/m)
        raw_json = m[1]
        begin
          parsed = JSON.parse(raw_json)
          return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # continue
        end
      end

      # Try to heuristically find an "intent" token inside text
      if m = cleaned.match(/"intent"\s*:\s*"([^"]+)"/i) || cleaned.match(/intent\s*[:=]\s*([a-z_]+)/i)
        intent = (m[1] || m[0]).to_s.downcase.gsub(/["':=\s]/, '')
        return { "intent" => intent, "raw" => cleaned, "confidence" => 0.0 }
      end

      return { "intent" => "unknown", "raw" => cleaned, "confidence" => 0.0 }
    end

    # fallback
    { "intent" => "unknown", "raw" => raw.to_s, "confidence" => 0.0 }
  end

  def stringify_keys_recursive(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_recursive(v) }
    when Array
      obj.map { |el| stringify_keys_recursive(el) }
    else
      obj
    end
  end

  # Non-DB intents we handle here
  def non_db_intent?(intent_json)
    return false unless intent_json.is_a?(Hash)
    intent = intent_json["intent"].to_s
    %w[greeting exit general_knowledge].include?(intent)
  end

  def handle_non_db_intent(intent_json)
    intent = intent_json["intent"].to_s
    case intent
    when "greeting"
      { reply: "Hello! 👋 How can I help you today? Try: 'show payors' or 'list students where branch is CSE'." }
    when "exit"
      { reply: "Okay — goodbye! Come back any time." }
    when "general_knowledge"
      { reply: "That looks like a general question. Would you like me to search the web?" }
    else
      { reply: "I couldn't interpret that. Try: 'show payors' or 'find students where cgpa > 8'." }
    end
  end

  def intent_reliable?(intent_json)
    return false unless intent_json.is_a?(Hash)
    # explicit DB intents are reliable
    return true if intent_json["intent"].present? && %w[select_filtered select_all select_record].include?(intent_json["intent"])
    return true if intent_json["confidence"].to_f >= 0.6

    # if a recognized table is present, accept
    if intent_json["table"].present?
      t = intent_json["table"].to_s.downcase
      normalized = LlmService.normalize_table_name(t) rescue t
      return true if SchemaService.schema_map.key?(normalized.to_sym)
    end

    false
  end

  def db_intent?(intent)
    %w[select_filtered select_all select_record].include?(intent.to_s)
  end

  # Handle DB-intents (select_filtered, select_all, select_record)
  def handle_db_intent(intent_json, user_text)
    intent = intent_json["intent"].to_s
    Rails.logger.info("[VoiceQuery] handle_db_intent intent=#{intent.inspect}, intent_json=#{intent_json.inspect}")

    if intent == "select_record" && intent_json["entity"].present?
      results = GenericResolver.new.find_by_value(intent_json["entity"])
      return render json: { type: "search_results", results: compact_results(results), source: "select_record_value_search" } if results.present?
      return render json: { message: "No records found for '#{intent_json["entity"]}'." }
    end

    table_raw = intent_json["table"].presence || guess_table_from_text(user_text)
    table_sym = LlmService.normalize_table_name(table_raw).to_sym rescue nil if table_raw.present?

    # infer table from filters if unknown
    if table_sym.blank? && intent_json["filters"].present?
      candidate_tables = candidate_tables_for_filters(intent_json["filters"])
      table_sym = candidate_tables.first if candidate_tables.one?
    end

    if table_sym.blank?
      Rails.logger.info("[VoiceQuery] couldn't determine table; intent_json=#{intent_json.inspect}")
      return render json: { message: "Couldn't determine which table to query. Please mention the table (e.g., students, payors)." }
    end

    unless SchemaService.schema_map.key?(table_sym)
      Rails.logger.info("[VoiceQuery] unknown table=#{table_sym}. Known=#{SchemaService.schema_map.keys.inspect}")
      return render json: { message: "Unknown table #{table_sym}. Possible tables: #{SchemaService.schema_map.keys.join(', ')}" }
    end

    builder = ActiveRecordQueryBuilder.new(SchemaService.schema_map)
    records = builder.build_and_run(table_sym, intent_json["filters"] || [], select_cols: intent_json["columns"], limit: intent_json["limit"] || 200)

    render json: { type: "query_results", table: table_sym, count: records.count, data: records.as_json, source: "db_query" }
  end

  def guess_table_from_text(text)
    return nil if text.blank?
    tc = text.to_s.downcase
    SchemaService.schema_map.keys.each do |k|
      return k.to_s if tc.include?(k.to_s)
    end
    nil
  end

  def candidate_tables_for_filters(filters)
    candidates = []
    Array(filters).each do |f|
      col = f["column"].to_s
      SchemaService.models_with_column(col).each do |m|
        candidates << m.name.downcase.to_sym
      end
    end
    candidates.uniq
  end

  def compact_results(results)
    results.transform_values do |rows|
      cols = rows.first&.attributes&.keys
      rows.limit(20).as_json(only: cols)
    end
  end
end










# app/controllers/voice_queries_controller.rb
# Improved Voice -> Intent -> DB flow
# - Accepts params[:text], params[:query] or params[:voice_query][:text]
# - Uses LlmService -> NlpService -> RegexFallbackService -> GenericResolver
# - Validates table & columns against SchemaService.schema_map
# - Robust normalization/parsing & helpful logging
class VoiceQueriesController < ApplicationController
  # POST /voice_queries/create
  # params: { text: "..." } or { query: "..." } or nested under :voice_query
  def create
    user_text = (params[:text] || params[:query] || params.dig(:voice_query, :text)).to_s.strip
    raise ArgumentError, "text param required" if user_text.blank?

    Rails.logger.info("[VoiceQuery] user_text=#{user_text.inspect}")

    # 1) Try LLM (may return Hash or String)
    raw_llm = safe_call { LlmService.extract_intent(user_text) }
    llm_result = normalize_intent_result(raw_llm)
    Rails.logger.info("[VoiceQuery] llm_result=#{llm_result.inspect}")

    # If LLM returned a clear non-DB intent (greeting, exit, general_knowledge), handle it immediately
    if non_db_intent?(llm_result)
      return render json: handle_non_db_intent(llm_result)
    end

    # If LLM looks reliable for DB query, use it
    if intent_reliable?(llm_result) && db_intent?(llm_result["intent"])
      Rails.logger.info("[VoiceQuery] using LLM for DB query")
      return handle_db_intent(llm_result, user_text)
    end

    # 2) NLP rule-based attempt
    raw_nlp = safe_call { NlpService.extract_intent(user_text) }
    nlp_result = normalize_intent_result(raw_nlp)
    Rails.logger.info("[VoiceQuery] nlp_result=#{nlp_result.inspect}")

    if non_db_intent?(nlp_result)
      return render json: handle_non_db_intent(nlp_result)
    end

    if intent_reliable?(nlp_result) && db_intent?(nlp_result["intent"])
      Rails.logger.info("[VoiceQuery] using NLP for DB query")
      return handle_db_intent(nlp_result, user_text)
    end

    # 3) Regex fallback
    raw_regex = safe_call { RegexFallbackService.extract_intent(user_text) }
    regex_result = normalize_intent_result(raw_regex)
    Rails.logger.info("[VoiceQuery] regex_result=#{regex_result.inspect}")

    if non_db_intent?(regex_result)
      return render json: handle_non_db_intent(regex_result)
    end

    if intent_reliable?(regex_result) && db_intent?(regex_result["intent"])
      Rails.logger.info("[VoiceQuery] using Regex for DB query")
      return handle_db_intent(regex_result, user_text)
    end

    # 4) Final fallback: full-text search across schema (trigram-backed)
    generic = GenericResolver.new
    results = safe_call { generic.find_by_value(user_text) } || {}
    if results.present?
      Rails.logger.info("[VoiceQuery] fallback: generic.find_by_value hits")
      return render json: { type: "search_results", results: compact_results(results), source: "trigram_fallback" }
    end

    Rails.logger.info("[VoiceQuery] no match for text; returning unknown")
    render json: { intent: "unknown", message: "I couldn't understand this as a DB query. Try: 'show students where branch is CSE'." }, status: 200
  rescue => e
    Rails.logger.error("[VoiceQuery] ERROR #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    render json: { error: e.message }, status: 500
  end

  private

  # Safe caller to protect controller flow
  def safe_call
    yield
  rescue => e
    Rails.logger.warn("[VoiceQuery] safe_call rescued: #{e.class}: #{e.message}")
    nil
  end

  # Turn various service outputs into a normalized Hash with string keys
  def normalize_intent_result(raw)
    return {} if raw.nil?

    # already a Hash
    if raw.is_a?(Hash)
      return stringify_keys_recursive(raw)
    end

    # If string: try to clean code fences, unescape, and parse JSON heuristically
    if raw.is_a?(String)
      cleaned = raw.dup
      cleaned.gsub!(/^\s*```(?:json)?\s*/i, '')
      cleaned.gsub!(/\s*```\s*$/i, '')
      cleaned.gsub!(/`([^`]*)`/, '\1')
      cleaned.gsub!(/\\n/, "\n")
      cleaned.gsub!(/\\\"/, '"')
      cleaned.strip!

      # Try to parse full JSON
      begin
        parsed = JSON.parse(cleaned)
        return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
      rescue JSON::ParserError
        # continue
      end

      # Try to extract first JSON object/array
      if m = cleaned.match(/(\{.*?\}|\[.*?\])/m)
        raw_json = m[1]
        begin
          parsed = JSON.parse(raw_json)
          return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # continue
        end
      end

      # Try to heuristically find an "intent" token inside text
      if m = cleaned.match(/"intent"\s*:\s*"([^"]+)"/i) || cleaned.match(/intent\s*[:=]\s*([a-z_]+)/i)
        intent = (m[1] || m[0]).to_s.downcase.gsub(/["':=\s]/, '')
        return { "intent" => intent, "raw" => cleaned, "confidence" => 0.0 }
      end

      return { "intent" => "unknown", "raw" => cleaned, "confidence" => 0.0 }
    end

    # fallback
    { "intent" => "unknown", "raw" => raw.to_s, "confidence" => 0.0 }
  end

  def stringify_keys_recursive(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_recursive(v) }
    when Array
      obj.map { |el| stringify_keys_recursive(el) }
    else
      obj
    end
  end

  # Non-DB intents we handle here
  def non_db_intent?(intent_json)
    return false unless intent_json.is_a?(Hash)
    intent = intent_json["intent"].to_s
    %w[greeting exit general_knowledge].include?(intent)
  end

  def handle_non_db_intent(intent_json)
    intent = intent_json["intent"].to_s
    case intent
    when "greeting"
      { reply: "Hello!  How can I help you today?" }
    when "exit"
      { reply: "Okay  goodbye! Come back any time." }
    when "general_knowledge"
      { reply: "That looks like a general question. Would you like me to search the web?" }
    else
      { reply: "I couldn't interpret that. Try: 'show payors' or 'find students where cgpa > 8'." }
    end
  end

  def intent_reliable?(intent_json)
    return false unless intent_json.is_a?(Hash)
    # explicit DB intents are reliable
    return true if intent_json["intent"].present? && %w[select_filtered select_all select_record].include?(intent_json["intent"])
    return true if intent_json["confidence"].to_f >= 0.6

    # if a recognized table is present, accept
    if intent_json["table"].present?
      t = intent_json["table"].to_s.downcase
      normalized = LlmService.normalize_table_name(t) rescue t
      return true if SchemaService.schema_map.key?(normalized.to_sym)
    end

    false
  end

  def db_intent?(intent)
    %w[select_filtered select_all select_record].include?(intent.to_s)
  end

  # Handle DB-intents (select_filtered, select_all, select_record)
  def handle_db_intent(intent_json, user_text)
    intent = intent_json["intent"].to_s
    Rails.logger.info("[VoiceQuery] handle_db_intent intent=#{intent.inspect}, intent_json=#{intent_json.inspect}")

    if intent == "select_record" && intent_json["entity"].present?
      results = GenericResolver.new.find_by_value(intent_json["entity"])
      return render json: { type: "search_results", results: compact_results(results), source: "select_record_value_search" } if results.present?
      return render json: { message: "No records found for '#{intent_json["entity"]}'." }
    end

    table_raw = intent_json["table"].presence || guess_table_from_text(user_text)
    normalized_table = LlmService.normalize_table_name(table_raw) if table_raw.present?
    table_sym = normalized_table.present? ? normalized_table.to_sym : nil

    # infer table from filters if unknown
    if table_sym.blank? && intent_json["filters"].present?
      candidate_tables = candidate_tables_for_filters(intent_json["filters"])
      table_sym = candidate_tables.first if candidate_tables.one?
    end

    if table_sym.blank?
      Rails.logger.info("[VoiceQuery] couldn't determine table; intent_json=#{intent_json.inspect}")
      return render json: { message: "Couldn't determine which table to query. Please mention the table (e.g., students, payors)." }
    end

    # If not found, try fuzzy match and suggest or auto-correct
    unless SchemaService.schema_map.key?(table_sym)
      guessed = schema_name_fuzzy_match(table_raw || table_sym.to_s)
      if guessed
        Rails.logger.info("[VoiceQuery] fuzzy-matched table '#{table_raw}' -> '#{guessed}'")
        table_sym = guessed.to_sym
      else
        Rails.logger.info("[VoiceQuery] unknown table=#{table_sym}. Known=#{SchemaService.schema_map.keys.inspect}")
        return render json: { message: "Unknown table '#{table_raw}'. Possible tables: #{SchemaService.schema_map.keys.join(', ')}" }
      end
    end

    # Validate filter columns against schema_map and sanitize
    if intent_json["filters"].present?
      intent_json["filters"].each do |f|
        col = f["column"].to_s
        next if SchemaService.schema_map[table_sym][:columns].key?(col)
        # fuzzy column match attempt
        alt = fuzzy_column_match(table_sym, col)
        if alt
          Rails.logger.info("[VoiceQuery] fuzzy column match '#{col}' -> '#{alt}' for table #{table_sym}")
          f["column"] = alt
        else
          return render json: { message: "Unknown column '#{col}' for table #{table_sym}. Available: #{SchemaService.schema_map[table_sym][:columns].keys.join(', ')}" }
        end
      end
    end

    # Validate requested columns
    if intent_json["columns"].present?
      clean_cols = []
      intent_json["columns"].each do |c|
        cstr = c.to_s
        if SchemaService.schema_map[table_sym][:columns].key?(cstr)
          clean_cols << cstr
        else
          alt = fuzzy_column_match(table_sym, cstr)
          if alt
            clean_cols << alt
          else
            Rails.logger.info("[VoiceQuery] dropping unknown requested column '#{cstr}' for table #{table_sym}")
          end
        end
      end
      intent_json["columns"] = clean_cols
    end

    builder = ActiveRecordQueryBuilder.new(SchemaService.schema_map)
    records = builder.build_and_run(table_sym, intent_json["filters"] || [], select_cols: intent_json["columns"], limit: intent_json["limit"] || 200)

    render json: { type: "query_results", table: table_sym, count: records.count, data: records.as_json, source: "db_query" }
  end

  # Try to guess table name directly from text when LLM didn't provide it
  def guess_table_from_text(text)
    return nil if text.blank?
    tc = text.to_s.downcase
    SchemaService.schema_map.keys.each do |k|
      return k.to_s if tc.include?(k.to_s)
    end
    nil
  end

  def candidate_tables_for_filters(filters)
    candidates = []
    Array(filters).each do |f|
      col = f["column"].to_s
      SchemaService.models_with_column(col).each do |m|
        candidates << m.name.downcase.to_sym
      end
    end
    candidates.uniq
  end

  def compact_results(results)
    results.transform_values do |rows|
      cols = rows.first&.attributes&.keys
      rows.limit(20).as_json(only: cols)
    end
  end

  # Fuzzy helpers

  def schema_name_fuzzy_match(name)
    return nil if name.blank?
    s = name.to_s.downcase
    # exact includes
    SchemaService.schema_map.keys.each do |k|
      return k.to_s if k.to_s == s || k.to_s.include?(s) || s.include?(k.to_s)
    end
    # Levenshtein-like simple heuristic: match by prefix
    SchemaService.schema_map.keys.each do |k|
      return k.to_s if k.to_s.start_with?(s[0,3]) && s.length >= 2
    end
    nil
  end

  def fuzzy_column_match(table_sym, col)
    return nil unless SchemaService.schema_map[table_sym]
    cols = SchemaService.schema_map[table_sym][:columns].keys
    exact = cols.find { |c| c == col }
    return exact if exact
    cols.find { |c| c.include?(col) || col.include?(c) || c.start_with?(col[0,3]) } # simple heuristics
  end
end
