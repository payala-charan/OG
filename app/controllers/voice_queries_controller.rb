  # app/controllers/voice_queries_controller.rb
  # Improved Voice -> Intent -> DB flow
  # - Accepts params[:text], params[:query] or params[:voice_query][:text]
  # - Uses LlmService -> NlpService -> RegexFallbackService -> GenericResolver
  # - Validates table & columns against SchemaService.schema_map
  # - Robust normalization/parsing & helpful logging
  class VoiceQueriesController < ApplicationController
    # The default limit for records returned by a database query.
    DEFAULT_LIMIT = 200
    # The limit for records returned by the generic/trigram fallback.
    GENERIC_FALLBACK_LIMIT = 20

    # Non-DB intents that are handled immediately.
    NON_DB_INTENTS = %w[greeting exit general_knowledge].freeze
    # DB-related intents that trigger a database query.
    DB_INTENTS = %w[select_filtered select_all select_record].freeze
    # Confidence score threshold for considering an intent reliable.
    CONFIDENCE_THRESHOLD = 0.6

    # POST /voice_queries/create
    # params: { text: "..." } or { query: "..." } or nested under :voice_query
    # def create
    #   user_text = (params[:text] || params[:query] || params.dig(:voice_query, :text)).to_s.strip
    #   raise ArgumentError, "text param required" if user_text.blank?

    #   Rails.logger.info("[VoiceQuery] 🗣️ User Text: #{user_text.inspect}")

    #   # Process through the intent hierarchy: LLM -> NLP -> Regex
    #   intent_result = process_intent_hierarchy(user_text)
    #   # Handle the final result
    #   if non_db_intent?(intent_result)
    #     return render json: handle_non_db_intent(intent_result)
    #   end
      
    #   # If a DB intent is determined, handle the database interaction
    #   if intent_reliable?(intent_result) && db_intent?(intent_result["intent"])
    #     Rails.logger.info("[VoiceQuery] ✅ Using reliable intent source: #{intent_result["source"]}")
    #     return handle_db_intent(intent_result, user_text)
    #   end

    #   # 4) Final fallback: full-text search across schema (trigram-backed)
    #   results = safe_call { GenericResolver.new.find_by_value(user_text) } || {}
    #   if results.present?
    #     Rails.logger.info("[VoiceQuery] 🔍 Fallback: generic.find_by_value hits (trigram)")
    #     return render json: { 
    #       type: "search_results", 
    #       results: compact_results(results, GENERIC_FALLBACK_LIMIT), 
    #       source: "trigram_fallback" 
    #     }
    #   end

    #   Rails.logger.info("[VoiceQuery] 🤷 No match for text; returning unknown")
    #   render json: { 
    #     intent: "unknown", 
    #     message: "I couldn't understand this as a structured DB query. Try a clear command like: 'show students where branch is CSE'." 
    #   }, status: 200
    # rescue ArgumentError => e
    #   render json: { error: "Client Error: #{e.message}" }, status: 400
    # rescue => e
    #   Rails.logger.error("[VoiceQuery] 🛑 ERROR #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    #   render json: { error: "Internal Server Error: #{e.message}" }, status: 500
    # end
    def create
      user_text = (params[:text] || params[:query] || params.dig(:voice_query, :text)).to_s.strip
      raise ArgumentError, "text param required" if user_text.blank?

      Rails.logger.info("[VoiceQuery] 🗣️ User Text: #{user_text.inspect}")

      intent_result = process_intent_hierarchy(user_text)

      # ----- 1. NON DB INTENTS -----
      if non_db_intent?(intent_result)
        response_data = handle_non_db_intent(intent_result)
        log_voice_query(user_text, response_data)
        return render json: response_data
      end

      # ----- 2. DB INTENTS -----
      if intent_reliable?(intent_result) && db_intent?(intent_result["intent"])
        Rails.logger.info("[VoiceQuery] ✅ Using reliable intent: #{intent_result["source"]}")

        response_data = handle_db_intent(intent_result, user_text)
        log_voice_query(user_text, response_data)
        return render json: response_data
      end

      # ----- 3. FALLBACK: TRIGRAM -----
      results = safe_call { GenericResolver.new.find_by_value(user_text) } || {}

      if results.present?
        response_data = {
          type: "search_results",
          results: compact_results(results, GENERIC_FALLBACK_LIMIT),
          source: "trigram_fallback"
        }
        log_voice_query(user_text, response_data)
        return render json: response_data
      end

      # ----- 4. UNKNOWN -----
      response_data = { 
        intent: "unknown",
        message: "I couldn't understand this as a structured DB query."
      }
      log_voice_query(user_text, response_data)
      render json: response_data

    rescue ArgumentError => e
      response_data = { error: "Client Error: #{e.message}" }
      log_voice_query(user_text, response_data)
      render json: response_data, status: 400

    rescue => e
      response_data = { error: "Internal Server Error: #{e.message}" }
      log_voice_query(user_text, response_data)
      render json: response_data, status: 500
    end


    private

    # --- Intent Resolution Pipeline ---

    def process_intent_hierarchy(user_text)
      # 1) LLM attempt
      raw_llm = safe_call { LlmService.extract_intent(user_text) }
      llm_result = normalize_intent_result(raw_llm).merge("source" => "llm")
      Rails.logger.info("[VoiceQuery] 🧠 LLM Result: #{llm_result.inspect}")
      return llm_result if non_db_intent?(llm_result) || (intent_reliable?(llm_result) && db_intent?(llm_result["intent"]))

      # 2) NLP rule-based attempt
      raw_nlp = safe_call { NlpService.extract_intent(user_text) }
      nlp_result = normalize_intent_result(raw_nlp).merge("source" => "nlp")
      Rails.logger.info("[VoiceQuery] 📜 NLP Result: #{nlp_result.inspect}")
      return nlp_result if non_db_intent?(nlp_result) || (intent_reliable?(nlp_result) && db_intent?(nlp_result["intent"]))

      # 3) Regex fallback
      raw_regex = safe_call { RegexFallbackService.extract_intent(user_text) }
      regex_result = normalize_intent_result(raw_regex).merge("source" => "regex")
      Rails.logger.info("[VoiceQuery] ⚙️ Regex Result: #{regex_result.inspect}")
      return regex_result
    end

    # --- DB Query Handling ---

    # Handles DB-intents (select_filtered, select_all, select_record)
    def handle_db_intent(intent_json, user_text)
      intent = intent_json["intent"].to_s
      Rails.logger.info("[VoiceQuery] 🏗️ Processing DB intent: #{intent.inspect}")

      # Specific handling for 'select_record' intent (often a simple search by value)
      if intent == "select_record" && intent_json["entity"].present?
        results = GenericResolver.new.find_by_value(intent_json["entity"])
        if results.present?
          return render json: { 
            type: "search_results", 
            results: compact_results(results, GENERIC_FALLBACK_LIMIT), 
            source: "select_record_value_search" 
          }
        end
        return render json: { message: "No records found for '#{intent_json["entity"]}'." }
      end

      # Normalize and validate table
      table_sym = determine_table_sym(intent_json, user_text)
      return render_table_error(intent_json["table"] || table_sym.to_s, table_sym.blank?) unless table_sym.present?

      # Clean and validate columns
      validated_intent = validate_and_clean_db_elements(table_sym, intent_json)
      return render json: validated_intent[:error_response] if validated_intent[:error_response].present?
      
      # Build and Run Query
      builder = ActiveRecordQueryBuilder.new(SchemaService.schema_map)
      limit = validated_intent["limit"].to_i.positive? ? validated_intent["limit"] : DEFAULT_LIMIT
      
      records = builder.build_and_run(
        table_sym, 
        validated_intent["filters"] || [], 
        select_cols: validated_intent["columns"], 
        limit: limit
      )

      #render json: format_db_results(table_sym, records, validated_intent["columns"])
      db_json = format_db_results(table_sym, records, validated_intent["columns"])
      summary_json = LlmService.summarize_results(db_json)
      #render json: summary_json
      #render plain: summary_json["summary_text"]
      { summary_text: summary_json["summary_text"] }
    end

    # Determine the target table symbol, including fallback/fuzzy matching
    def determine_table_sym(intent_json, user_text)
      table_raw = intent_json["table"].presence || guess_table_from_text(user_text)
      normalized_table = LlmService.normalize_table_name(table_raw) if table_raw.present?
      table_sym = normalized_table.present? ? normalized_table.to_sym : nil

      # Infer table from filters if unknown
      if table_sym.blank? && intent_json["filters"].present?
        candidate_tables = candidate_tables_for_filters(intent_json["filters"])
        table_sym = candidate_tables.first if candidate_tables.one?
      end

      # If not found, try fuzzy match and auto-correct
      unless table_sym.present? && SchemaService.schema_map.key?(table_sym)
        guessed = schema_name_fuzzy_match(table_raw || table_sym.to_s)
        if guessed
          Rails.logger.info("[VoiceQuery] 💡 Fuzzy-matched table '#{table_raw}' -> '#{guessed}'")
          table_sym = guessed.to_sym
        end
      end

      table_sym.present? && SchemaService.schema_map.key?(table_sym) ? table_sym : nil
    end

    # Renders an error response for unknown/undetermined table
    def render_table_error(table_raw, undetermined)
      message = if undetermined
        "Couldn't determine which table to query. Please mention the table (e.g., 'students', 'payors')."
      else
        "Unknown table '#{table_raw}'. Possible tables: #{SchemaService.schema_map.keys.join(', ')}"
      end
      Rails.logger.info("[VoiceQuery] 🚫 Table Error: #{message}")
      render json: { message: message }
    end

    # Validates and cleans filter and column names against the schema
    def validate_and_clean_db_elements(table_sym, intent_json)
      # Ensure a mutable copy of the intent for cleaning
      validated_intent = intent_json.dup

      # 1. Validate and clean Filters
      if validated_intent["filters"].present?
        validated_intent["filters"].each do |f|
          col = f["column"].to_s
          unless SchemaService.schema_map[table_sym][:columns].key?(col)
            alt = fuzzy_column_match(table_sym, col)
            if alt
              Rails.logger.info("[VoiceQuery] 💡 Fuzzy column match: '#{col}' -> '#{alt}' for table #{table_sym}")
              f["column"] = alt
            else
              return { error_response: { message: "Unknown column '#{col}' for table #{table_sym}. Available: #{SchemaService.schema_map[table_sym][:columns].keys.join(', ')}" } }
            end
          end
        end
      end

      # 2. Validate and clean requested Columns
      if validated_intent["columns"].present?
        clean_cols = []
        validated_intent["columns"].each do |c|
          cstr = c.to_s
          if SchemaService.schema_map[table_sym][:columns].key?(cstr)
            clean_cols << cstr
          else
            alt = fuzzy_column_match(table_sym, cstr)
            if alt
              clean_cols << alt
            else
              Rails.logger.info("[VoiceQuery] ⚠️ Dropping unknown requested column '#{cstr}' for table #{table_sym}")
            end
          end
        end
        validated_intent["columns"] = clean_cols
      end
      
      validated_intent
    end

    # Standardized result format for database query results
    def format_db_results(table_sym, records, requested_columns)
      # --- Custom Formatting for 'payors' Table ---
      # if table_sym == :payors || table_sym == :payor
      #   # Check if records have the necessary columns for summarization before proceeding
      #   if records.any? && records.first.respond_to?(:generic_name) && records.first.respond_to?(:name)
      #     return group_and_summarize_payors_by_generic_name(records, table_sym.to_s)
      #   end
      # end
      # -----------------------------------------------

      # Default JSON formatting (for all other tables)
      # Determine the columns to include in the final JSON
      cols_to_include = if requested_columns.present?
        requested_columns.map(&:to_s)
      elsif records.first.present?
        # If no specific columns, use all available columns in the first record
        records.first.attributes.keys
      else
        [] # Empty set if no records
      end

      { 
        type: "query_results", 
        table: table_sym.to_s, 
        count: records.count, 
        columns: cols_to_include,
        data: records.as_json(only: cols_to_include), 
        source: "db_query" 
      }
    end
    
    # Helper method to group Payor records and generate a summary reply
    def group_and_summarize_payors_by_generic_name(records, table_name)
      # Group the records by the 'generic_name' column
      # Note: Assumes records are ActiveRecord objects with `generic_name` and `name` attributes
      grouped_data = records.group_by(&:generic_name)

      summary_lines = []
      
      grouped_data.each do |generic_name, payor_records|
        # Skip if generic_name is missing or nil (shouldn't happen with valid data)
        next if generic_name.blank? 

        # Collect all unique payor names for the current generic_name
        payor_names = payor_records.map(&:name).compact.uniq
        
        # Format the list of payor names using `to_sentence` for natural language
        payors_list = payor_names.to_sentence(two_words_connector: ' and ', last_word_connector: ', and ')
        
        # Generate the summary sentence
        if payor_names.one?
          summary_lines << "For the generic #{generic_name.capitalize} , the payor is #{payors_list}."
        else
          summary_lines << "For the generic #{generic_name.capitalize}, the payors are #{payors_list}."
        end
      end

      # Join all summary sentences into a single, cohesive message
      full_summary = summary_lines.join("\n")
      
      # Return the result in a 'reply' format which is suitable for direct output
      {
        type: "query_summary",
        table: table_name,
        count: records.count,
        reply: full_summary,
        source: "db_summary"
      }
    end

    # --- Utility Methods ---

    # Safe caller to protect controller flow
    def safe_call
      yield
    rescue => e
      Rails.logger.warn("[VoiceQuery] ⚠️ safe_call rescued: #{e.class}: #{e.message}")
      nil
    end

    # Turn various service outputs into a normalized Hash with string keys
    def normalize_intent_result(raw)
      return {} if raw.nil?

      # already a Hash
      if raw.is_a?(Hash)
        return stringify_keys_recursive(raw)
      end

      # If string: robustly clean and parse JSON heuristically
      if raw.is_a?(String)
        cleaned = raw.dup
        
        # Clean LLM markdown/fencing and basic escapes
        cleaned.gsub!(/^\s*```(?:json)?\s*/i, '') # remove leading fences
        cleaned.gsub!(/\s*```\s*$/i, '')           # remove trailing fences
        cleaned.gsub!(/`([^`]*)`/, '\1')           # remove inline backticks
        cleaned.gsub!(/\\n/, "\n")
        cleaned.gsub!(/\\\"/, '"')
        cleaned.strip!

        # 1. Try to parse full JSON
        begin
          parsed = JSON.parse(cleaned)
          return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # continue
        end

        # 2. Try to extract first JSON object/array
        if m = cleaned.match(/(\{.*?\}|\[.*?\])/m)
          raw_json = m[1]
          begin
            parsed = JSON.parse(raw_json)
            return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
          rescue JSON::ParserError
            # continue
          end
        end

        # 3. Try to heuristically find an "intent" token inside text as a last resort
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

    # Checks if the intent is a non-DB intent
    def non_db_intent?(intent_json)
      return false unless intent_json.is_a?(Hash)
      NON_DB_INTENTS.include?(intent_json["intent"].to_s)
    end

    # Handles non-DB intents, generating a simple response
    def handle_non_db_intent(intent_json)
      intent = intent_json["intent"].to_s
      case intent
      when "greeting"
        { reply: "Hello! How can I help you today?" }
      when "exit"
        { reply: "Okay, goodbye! Come back any time." }
      when "general_knowledge"
        { reply: "That looks like a general question. Would you like me to search the web for that?" }
      else
        { reply: "I couldn't interpret that. Try: 'show payors' or 'find students where cgpa > 8'." }
      end
    end

    # Determines if the intent result is reliable enough to be used.
    def intent_reliable?(intent_json)
      return false unless intent_json.is_a?(Hash)

      # 1. Explicit DB intents are highly reliable
      return true if DB_INTENTS.include?(intent_json["intent"].to_s)

      # 2. High confidence score is reliable
      return true if intent_json["confidence"].to_f >= CONFIDENCE_THRESHOLD

      # 3. If a recognized, valid table is present, it's reliable
      if intent_json["table"].present?
        t = intent_json["table"].to_s.downcase
        # Use safe_call in case normalization fails or is undefined
        normalized = safe_call { LlmService.normalize_table_name(t) } || t 
        return true if SchemaService.schema_map.key?(normalized.to_sym)
      end

      false
    end

    # Checks if the intent is a DB-related intent
    def db_intent?(intent)
      DB_INTENTS.include?(intent.to_s)
    end

    # Try to guess table name directly from text when LLM didn't provide it
    def guess_table_from_text(text)
      return nil if text.blank?
      tc = text.to_s.downcase
      # Prioritize exact word match in the text
      SchemaService.schema_map.keys.each do |k|
        return k.to_s if tc.include?(" #{k.to_s} ") || tc.start_with?(k.to_s)
      end
      nil
    end

    # Finds candidate tables that contain all specified filters/columns
    def candidate_tables_for_filters(filters)
      candidates = []
      Array(filters).each do |f|
        col = f["column"].to_s
        # Assumes SchemaService.models_with_column returns ActiveRecord Models
        SchemaService.models_with_column(col).each do |m|
          candidates << m.name.downcase.to_sym
        end
      end
      # Simple logic to get unique candidate tables for *any* column:
      candidates.uniq 
    end

    # Compresses the full results Hash (table_name => [record, record, ...]) 
    # by limiting the number of records for display in fallback scenarios.
    def compact_results(results, limit = GENERIC_FALLBACK_LIMIT)
      results.transform_values do |rows|
        # Only include attributes that exist on the model
        cols = rows.first&.attributes&.keys || []
        # Use `as_json` with `only` to explicitly control the data passed
        rows.limit(limit).as_json(only: cols)
      end
    end

    # Fuzzy helpers (simplistic Levenshtein/prefix check)

    def schema_name_fuzzy_match(name)
      return nil if name.blank?
      s = name.to_s.downcase
      # 1. Exact or near-exact includes
      SchemaService.schema_map.keys.each do |k|
        k_s = k.to_s
        # Full match, or one includes the other (e.g., 'std' for 'students')
        return k_s if k_s == s || k_s.include?(s) || s.include?(k_s) 
      end
      # 2. Levenshtein-like simple heuristic: match by prefix
      SchemaService.schema_map.keys.each do |k|
        return k.to_s if k.to_s.start_with?(s[0,3]) && s.length >= 2
      end
      nil
    end

    def fuzzy_column_match(table_sym, col)
      return nil unless SchemaService.schema_map[table_sym]
      cols = SchemaService.schema_map[table_sym][:columns].keys
      col_down = col.to_s.downcase
      
      # 1. Exact match
      exact = cols.find { |c| c == col_down }
      return exact if exact

      # 2. Simple heuristics: inclusion or prefix match
      cols.find do |c| 
        c.include?(col_down) || col_down.include?(c) || c.start_with?(col_down[0,3]) 
      end 
    end
    def log_voice_query(query, response_data)
      result = response_data.is_a?(Hash) && response_data[:error].present? ? "Fail" : "Pass"

      VoiceQueryLog.create!(
        query: query,
        response: response_data.to_json,
        result: result
      )

      # Keep only last 20 records
      VoiceQueryLog.order(created_at: :desc).offset(20).destroy_all
    end

  end