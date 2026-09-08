require 'httparty'

class LlmService
  PROVIDER = ENV.fetch("LLM_PROVIDER", "google") # "openai", "google", or "mock"

 def self.extract_intent(user_text)
    case PROVIDER
    when "openai" then openai_extract_intent(user_text)
    when "google" then google_extract_intent(user_text)
    else mock_extract_intent(user_text)
    end
  rescue => e
    Rails.logger.warn("LlmService.extract_intent error: #{e.class}: #{e.message}")
    mock_extract_intent(user_text)
  end


  # ---------- MOCK for dev and as a free fallback ----------
  def self.mock_extract_intent(text)
    t = text.to_s.strip
    # Very small heuristic patterns: try to pick table names and simple filters
    # Lowercase for matching
    lc = t.downcase

    # detect simple select_all 'show all students'
    if lc.match?(/\b(show|list|display|all)\b.*\b(students|payors|insurances|ogs|payor preferences|payor_preferences|samples|users|students|payment_factors|name_matches|uploaded_files|documents)\b/)
      table = lc.match(/\b(students|payors|insurances|ogs|payor preferences|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b/)[0]
      return { "intent" => "select_all", "table" => normalize_table_name(table), "confidence" => 0.9 }
    end

    # detect simple filter like 'students with branch cse' or 'students whose branch is CSE'
    if m = lc.match(/\b(students|payors|insurances|ogs|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b.*\b(with|where|whose|having)\b.*\b([a-z0-9_\- ]+)\b/)
      table = normalize_table_name(m[1])
      # naive attempt to split column/value by 'is', 'equals', 'like', '>' '<' keywords
      if fv = m[0].match(/(\b[a-z_]+\b)\s*(?:is|=|equals|like|:)?\s*([a-z0-9_\- ]+)/)
        col = fv[1]
        val = fv[2]
        return { "intent" => "select_filtered", "table" => table, "filters" => [{ "column" => col, "op" => "=", "value" => val.strip }], "confidence" => 0.7 }
      end
      return { "intent" => "select_filtered", "table" => table, "filters" => [], "confidence" => 0.6 }
    end

    # single token short queries probably entity search:
    if t.split.size <= 3
      return { "intent" => "select_record", "entity" => t, "confidence" => 0.6 }
    end

    { "intent" => "unknown", "raw" => t, "confidence" => 0.0 }
  end

  # ---------- OpenAI (optional) - only if you set PROVIDER to "openai" and have an API key ----------
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
      text = res.parsed_response.dig("choices", 0, "message", "content")
      JSON.parse(text) rescue { "intent" => "unknown", "raw" => text }
    else
      raise "OpenAI error: #{res.code} #{res.body}"
    end
  end

  # ---------- Google Vertex AI (optional) - only if you set PROVIDER to "google" and configure credentials ----------
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
      text = res.parsed_response.dig("candidates", 0, "content", "parts", 0, "text")
      JSON.parse(text) rescue { "intent" => "unknown", "raw" => text }
    else
      raise "Google API error: #{res.code} #{res.body}"
    end
  end


  # Prompt builder used by paid/opt-in providers
  def self.build_intent_prompt(user_text)
    <<~PROMPT
      Extract a structured intent JSON from the following user text and return ONLY JSON.
      Allowed intents: select_filtered, select_all, select_record, general_knowledge, greeting, exit, unknown.
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

  def self.normalize_table_name(raw)
    s = raw.to_s.downcase
    case s
    when /payor/
      "payors"
    when /insurance/
      "insurances"
    when /og\b|ogs?/
      "ogs"
    when /payor.?preference/
      "payor_preferences"
    when /uploaded.?file/
      "uploaded_files"
    when /name.?match/
      "name_matches"
    else
      s.gsub(/\s+/, "_")
    end
  end
end












# app/services/llm_service.rb
require 'httparty'

class LlmService
  # Keep provider choice lowercase for simplicity
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

  # ---------- MOCK for dev and as a free fallback ----------
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
    schema_json = SchemaService.schema_map.to_json
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

  def self.normalize_table_name(raw)
    s = raw.to_s.downcase
    case s
    when /payor/ then "payor"
    when /insurance/ then "insurance"
    when /og\b|ogs?/ then "og"
    when /payor.?preference/ then "payor_preference"
    when /uploaded.?file/ then "uploaded_file"
    when /name.?match/ then "name_matche"
    else s.gsub(/\s+/, "_")
    end
  end
end
