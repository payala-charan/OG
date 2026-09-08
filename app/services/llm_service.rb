# app/services/llm_service.rb
# LLM intent extractor with schema-aware prompting and robust provider parsing.
# PROVIDER: "google", "openai", or "mock"
require 'httparty'

class LlmService
  PROVIDER = (ENV["LLM_PROVIDER"] || "google").to_s.downcase # "openai", "google", or "mock"

  def self.extract_intent(user_text)
    case PROVIDER
    when "openai" then openai_extract_intent(user_text)
    when "google" then google_extract_intent(user_text)
    else mock_extract_intent(user_text)
    end
  rescue => e
    Rails.logger.warn("[LlmService] extract_intent error: #{e.class}: #{e.message}")
    mock_extract_intent(user_text)
  end

  # ---------- MOCK (fallback) ----------
  def self.mock_extract_intent(text)
    t = text.to_s.strip
    lc = t.downcase

    # select_all
    if lc.match?(/\b(show|list|display|all|give me|fetch)\b.*\b(students|payors|insurances|ogs|payor preferences|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b/)
      table = lc.match(/\b(students|payors|insurances|ogs|payor preferences|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b/)[0]
      return { "intent" => "select_all", "table" => normalize_table_name(table), "confidence" => 0.9 }
    end

    # simple filter
    if m = lc.match(/\b(students|payors|insurances|ogs|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b.*\b(with|where|whose|having)\b.*\b([a-z0-9_\- ]+)\b/)
      table = normalize_table_name(m[1])
      if fv = m[0].match(/(\b[a-z_]+\b)\s*(?:is|=|equals|like|:)?\s*([a-z0-9_\- ]+)/)
        col = fv[1]; val = fv[2]
        return { "intent" => "select_filtered", "table" => table, "filters" => [{ "column" => col, "op" => "=", "value" => val.strip }], "confidence" => 0.7 }
      end
      return { "intent" => "select_filtered", "table" => table, "filters" => [], "confidence" => 0.6 }
    end

    # short entity search
    if t.split.size <= 3
      return { "intent" => "select_record", "entity" => t, "confidence" => 0.6 }
    end

    { "intent" => "unknown", "raw" => t, "confidence" => 0.0 }
  end

  # ---------- OpenAI ----------
  def self.openai_extract_intent(user_text)
    api_key = ENV.fetch("OPENAI_API_KEY")
    url = "https://api.openai.com/v1/chat/completions"
    prompt = build_intent_prompt(user_text)

    body = {
      model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
      messages: [
        { role: "system", content: "You are an intent extractor that returns only JSON." },
        { role: "user", content: prompt }
      ],
      temperature: 0.0,
      max_tokens: 512
    }

    res = HTTParty.post(url,
      headers: { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" },
      body: body.to_json
    )

    if res.code == 200
      raw_text = res.parsed_response.dig("choices", 0, "message", "content").to_s
      Rails.logger.debug("[LlmService][openai] raw_text: #{raw_text.inspect}")
      cleaned = clean_provider_text(raw_text)
      Rails.logger.debug("[LlmService][openai] cleaned: #{cleaned.inspect}")
      parse_provider_json_or_fallback(cleaned, raw_text)
    else
      raise "OpenAI error: #{res.code} #{res.body}"
    end
  end

  # ---------- Google Vertex AI (Gemini) ----------
  def self.google_extract_intent(user_text)
    api_key = ENV.fetch("GOOGLE_API_KEY")
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}"

    prompt = build_intent_prompt(user_text)

    body = {
      contents: [
        {
          parts: [
            { text: prompt }
          ]
        }
      ]
    }

    res = HTTParty.post(url,
      headers: { "Content-Type" => "application/json" },
      body: body.to_json
    )

    if res.code == 200
      raw_text = res.parsed_response.dig("candidates", 0, "content", "parts", 0, "text").to_s
      Rails.logger.debug("[LlmService][google] raw_text: #{raw_text.inspect}")
      cleaned = clean_provider_text(raw_text)
      Rails.logger.debug("[LlmService][google] cleaned: #{cleaned.inspect}")
      parse_provider_json_or_fallback(cleaned, raw_text)
    else
      raise "Google API error: #{res.code} #{res.body}"
    end
  end

  # ---------- Helpers ----------
  def self.parse_provider_json_or_fallback(cleaned_text, original_raw)
    # Try full parse
    begin
      parsed = JSON.parse(cleaned_text)
      return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
    rescue JSON::ParserError
      # continue
    end

    # Try to extract the first JSON object/array block
    if m = cleaned_text.match(/(\{.*\}|\[.*\])/m)
      raw_json = m[1]
      begin
        parsed = JSON.parse(raw_json)
        return stringify_keys_recursive(parsed) if parsed.is_a?(Hash)
      rescue JSON::ParserError
        # continue
      end
    end

    # If nothing parseable, return unknown with raw cleaned text (controller will attempt further heuristics)
    { "intent" => "unknown", "raw" => cleaned_text.presence || original_raw.to_s, "confidence" => 0.0 }
  end

  def self.clean_provider_text(text)
    return "" if text.nil?
    s = text.dup

    # Remove opening code fence lines like ```json or ``` json
    s.gsub!(/^\s*```(?:json)?\s*/i, '')
    # Remove trailing closing fence
    s.gsub!(/\s*```\s*$/i, '')

    # Remove inline backticks
    s.gsub!(/`([^`]*)`/, '\1')

    # Unescape escaped newlines and escaped quotes
    s.gsub!(/\\n/, "\n")
    s.gsub!(/\\\"/, '"')

    s.strip
  end

  def self.stringify_keys_recursive(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_recursive(v) }
    when Array
      obj.map { |el| stringify_keys_recursive(el) }
    else
      obj
    end
  end

  # ---------- Prompt builder ----------
  def self.build_intent_prompt(user_text)
    # Provide a compact JSON representation of schema (table => [cols])
    schema_json = SchemaService.simple_map.to_json
    <<~PROMPT
      Extract a structured intent JSON from the following user text and return ONLY JSON.
      Allowed intents: select_filtered, select_all, select_record, general_knowledge, greeting, exit, unknown.

      Database schema (tables and their columns). YOU MUST output table and column names EXACTLY as shown:
      #{schema_json}

      Do NOT invent tables.
      Do NOT invent column names.
      Only choose from the provided schema.

      User query:
      "#{user_text}"
      Provide:
      - intent
      - table (optional)
      - filters: [{ "column": "...", "op": "=", "value": ... }]
      - columns: optional array of columns to return
      - entity: optional string
      - confidence: 0..1

      Example:
      Input: "Show all students from CSE branch with cgpa above 8"
      Output:
      {
        "intent": "select_filtered",
        "table": "students",
        "filters": [
          { "column": "branch", "op": "=", "value": "CSE" },
          { "column": "cgpa", "op": ">", "value": 8 }
        ],
        "columns": ["name","cgpa","branch"],
        "confidence": 0.95
      }

      Input: "#{user_text}"
    PROMPT
  end

  # Normalize freeform table name from LLM/NLP/regex into canonical schema key
  def self.normalize_table_name(raw)
    s = raw.to_s.downcase.strip
    return "" if s.blank?

    # Try schema keys first: singular and plural
    singular = s.singularize
    plural   = s.pluralize

    if SchemaService.schema_map.key?(singular.to_sym)
      return singular
    elsif SchemaService.schema_map.key?(plural.to_sym)
      return plural
    end

    # Pattern based fallback (common names)
    case s
    when /^payor/ then "payor"
    when /^payors$/ then "payor"
    when /^insurance/ then "insurance"
    when /^og(s)?$/ then "og"
    when /^payor.?preference/ then "payor_preference"
    when /^uploaded.?file/ then "uploaded_file"
    when /^name.?match/ then "name_match"
    else
      # fallback to singularize cleaned
      singular
    end
  end
  # ============================================================
  # SUMMARY GENERATION (NEW)
  # ============================================================
  def self.summarize_results(result_json)
    begin
      case PROVIDER
      when "openai"
        openai_summarize_results(result_json)
      when "google"
        google_summarize_results(result_json)
      else
        mock_summarize_results(result_json)
      end
    rescue => e
      Rails.logger.warn("[LlmService] summarize_results error: #{e.class}: #{e.message}")
      mock_summarize_results(result_json)
    end
  end

  # ---------- MOCK fallback ----------
  def self.mock_summarize_results(json)
    {
      "type" => "summary",
      "table" => json["table"],
      "count" => json["count"],
      "summary_text" => "Summary unavailable (mock mode). #{json['count']} records found in #{json['table']}."
    }
  end

  # ---------- GOOGLE (Gemini) ----------
  def self.google_summarize_results(result_json)
    api_key = ENV.fetch("GOOGLE_API_KEY")
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}"

    prompt = build_summary_prompt(result_json)

    body = {
      contents: [
        {
          parts: [
            { text: prompt }
          ]
        }
      ]
    }

    res = HTTParty.post(url,
      headers: { "Content-Type" => "application/json" },
      body: body.to_json
    )

    if res.code == 200
      raw_text = res.parsed_response.dig("candidates", 0, "content", "parts", 0, "text").to_s
      cleaned = clean_provider_text(raw_text)
      parsed = parse_provider_json_or_fallback(cleaned, raw_text)
      return parsed
    else
      raise "Google API error: #{res.code} #{res.body}"
    end
  end

  # ---------- OPENAI ----------
  def self.openai_summarize_results(result_json)
    api_key = ENV.fetch("OPENAI_API_KEY")
    url = "https://api.openai.com/v1/chat/completions"
    prompt = build_summary_prompt(result_json)

    body = {
      model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
      messages: [
        { role: "system", content: "You are a data summarizer that returns ONLY valid JSON." },
        { role: "user", content: prompt }
      ],
      temperature: 0.3,
      max_tokens: 300
    }

    res = HTTParty.post(url,
      headers: { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" },
      body: body.to_json
    )

    if res.code == 200
      raw_text = res.parsed_response.dig("choices", 0, "message", "content").to_s
      cleaned = clean_provider_text(raw_text)
      parsed = parse_provider_json_or_fallback(cleaned, raw_text)
      return parsed
    else
      raise "OpenAI error: #{res.code} #{res.body}"
    end
  end

  # ---------- SUMMARY PROMPT ----------
  def self.build_summary_prompt(result_json)
    <<~PROMPT
      You are a professional data summarizer.
      Summarize the following database results into a simple, clear, human-readable summary.

      IMPORTANT:
      - Your output MUST be ONLY JSON.
      - Do NOT include raw records.
      - Provide a short, useful summary for end users.
      - Always include: type, table, count, summary_text.

      Example output:
      {
        "type": "summary",
        "table": "payor",
        "count": 35,
        "summary_text": "There are 35 payors. Top payors include Aetna, Cigna, Humana, and United. All payors use the generic name Bevacizumab."
      }

      Database result to summarize:
      #{result_json.to_json}
    PROMPT
  end

end
