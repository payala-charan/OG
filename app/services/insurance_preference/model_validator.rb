# frozen_string_literal: true

require "httparty"

module InsurancePreference
  class ModelValidator
    SKIP_STATUSES = %w[NO_MASTER_MAPPING NO_GROUP_ASSIGNED].freeze

    def initialize(row, provider: Config::LLM_PROVIDER, model: Config::LLM_MODEL)
      @row = row
      @provider = provider.to_s.downcase
      @model = model
    end

    def call
      raw = request_json
      model_status = normalize_status(raw["validation_status"] || raw["verdict"] || raw["status"])
      {
        model_name: @model,
        agrees_with_code: agrees?(model_status, @row.validation_status),
        model_validation_status: model_status,
        model_missing_insurances: Array(raw["missing_insurances"] || raw["missing"]).join("\n"),
        model_notes: raw["notes"] || raw["reasoning"].to_s,
        raw_response: raw
      }
    rescue StandardError => e
      {
        model_name: @model,
        agrees_with_code: false,
        model_validation_status: "ERROR",
        model_missing_insurances: "",
        model_notes: e.message,
        raw_response: { "error" => e.message }
      }
    end

    private

    def agrees?(model_status, code_status)
      category(model_status) == category(code_status)
    end

    def category(status)
      case status.to_s.upcase
      when "PASS" then "PASS"
      when "REVIEW", "REVIEW_SPELLING" then "REVIEW"
      when "FAIL", "FAIL_MISSING" then "FAIL"
      else status.to_s.upcase
      end
    end

    def normalize_status(value)
      text = value.to_s.upcase
      return "PASS" if text.include?("PASS")
      return "REVIEW" if text.include?("REVIEW")
      return "FAIL" if text.include?("FAIL")

      text.presence || "UNKNOWN"
    end

    def request_json
      case @provider
      when "openai" then openai_json
      when "google" then google_json
      else mock_json
      end
    end

    def prompt
      <<~PROMPT
        You independently verify whether a biosimilar product insurance list covers every plan required by a master preference table.

        Return ONLY JSON with keys:
        validation_status (PASS, REVIEW, or FAIL),
        missing_insurances (array of strings),
        spelling_mismatches (array of {master, sheet}),
        extra_insurances (array of strings),
        notes (short reasoning).

        Rules:
        - Do not use naive substring matching. "MEDICAID VIRGINIA" is not the same plan as "EMERGENCY MEDICAID VIRGINIA".
        - Treat obvious typos (one dropped letter) as REVIEW, not FAIL.
        - Treat trailing parenthetical variants such as "INNOVAGE (PACE)" vs "INNOVAGE" as present.
        - Treat two required plans concatenated with a space instead of a comma as present.

        Generic name: #{@row.generic_name}
        Matched brand: #{@row.matched_brand_column}
        Required plans: #{Array(@row.missing_insurances).concat(required_from_row).uniq}
        Actual insurance text: #{@row.source_column_used}: see missing/extras context
        Code validation status (do not copy blindly): #{@row.validation_status}
        Required list: #{required_from_row.to_json}
        Actual list extras context missing: #{Array(@row.missing_insurances).to_json}
        Actual extras: #{Array(@row.extra_insurances).to_json}
      PROMPT
    end

    def required_from_row
      blacks_and_reds = Array(@row.claude_insurances_json).filter_map do |run|
        next if run["color"] == "yellow"

        run["text"]
      end
      blacks_and_reds.flat_map { |text| Text.split_plan_names(text) }
    end

    def mock_json
      {
        "validation_status" => category(@row.validation_status) == "PASS" ? "PASS" : category(@row.validation_status),
        "missing_insurances" => Array(@row.missing_insurances),
        "notes" => "Mock model validation mirrored the code status.",
        "provider" => "mock"
      }
    end

    def openai_json
      api_key = ENV.fetch("OPENAI_API_KEY")
      body = {
        model: @model,
        messages: [
          { role: "system", content: "You return only JSON." },
          { role: "user", content: prompt }
        ],
        temperature: 0.0,
        max_tokens: 800
      }
      res = HTTParty.post(
        "https://api.openai.com/v1/chat/completions",
        headers: { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" },
        body: body.to_json
      )
      raise "OpenAI error: #{res.code} #{res.body}" unless res.code == 200

      parse_json(res.parsed_response.dig("choices", 0, "message", "content").to_s)
    end

    def google_json
      api_key = ENV.fetch("GOOGLE_API_KEY")
      model = ENV.fetch("INSURANCE_PREF_GEMINI_MODEL", "gemini-2.0-flash")
      url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
      res = HTTParty.post(
        url,
        headers: { "Content-Type" => "application/json" },
        body: { contents: [{ parts: [{ text: prompt }] }] }.to_json
      )
      raise "Google API error: #{res.code} #{res.body}" unless res.code == 200

      parse_json(res.parsed_response.dig("candidates", 0, "content", "parts", 0, "text").to_s)
    end

    def parse_json(text)
      cleaned = LlmService.clean_provider_text(text)
      parsed = LlmService.parse_provider_json_or_fallback(cleaned, text)
      parsed.is_a?(Hash) ? parsed : { "raw" => text, "validation_status" => "UNKNOWN" }
    end
  end
end
