# frozen_string_literal: true

require "set"

module InsurancePreference
  module Text
    module_function

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def present?(value)
      !blank?(value)
    end

    def stringify(value)
      value.to_s
    end

    def collapse_ws(value)
      stringify(value).gsub(/[[:space:]]+/, " ").strip
    end

    def exact_key(value)
      collapse_ws(value).downcase
    end

    def tokens(value)
      collapse_ws(value).upcase.scan(/[A-Z0-9]+/)
    end

    def sorted_token_key(value)
      tokens(value).sort.join(" ")
    end

    def token_jaccard(a, b)
      ta = tokens(a).to_set
      tb = tokens(b).to_set
      return 1.0 if ta.empty? && tb.empty?
      return 0.0 if ta.empty? || tb.empty?

      (ta & tb).size.to_f / (ta | tb).size
    end

    def similarity(a, b)
      [
        SequenceMatcher.new(collapse_ws(a), collapse_ws(b)).ratio,
        token_jaccard(a, b)
      ].max
    end

    def strip_trailing_paren(value)
      collapse_ws(value).sub(/\s*\([^)]*\)\s*\z/, "").strip
    end

    def split_plan_names(value)
      collapse_ws(value).split(/\s*,\s*/).map { |part| collapse_ws(part) }.reject(&:empty?)
    end

    def header_key(value)
      collapse_ws(value).downcase.tr("_", " ").gsub(/[^a-z0-9 ]+/, " ").squeeze(" ").strip
    end

    def hcpcs_code(value)
      m = collapse_ws(value).upcase.match(/(?:\s|^)([A-Z]\d{4})\s*\z/)
      m&.[](1)
    end

    def strip_leading_rank(value)
      collapse_ws(value).sub(/\A\(\d+\)\s*/, "")
    end
  end
end
