# frozen_string_literal: true

module InsurancePreference
  class BrandMatcher
    Match = Struct.new(
      :method,
      :brand,
      :confidence,
      :notes,
      keyword_init: true
    )

    def initialize(columns)
      @columns = Array(columns)
    end

    def match(generic_name:, group:, tab_found:)
      return Match.new(method: "NO_TAB", brand: nil, confidence: 0.0, notes: "No Master tab for group") unless tab_found
      return Match.new(method: "NO_GROUP", brand: nil, confidence: 0.0, notes: "No generic name group") if Text.blank?(group)

      override = override_for(group, generic_name)
      if override
        brand = find_column_by_header(override)
        if brand
          return Match.new(method: "OVERRIDE", brand: brand, confidence: 1.0, notes: "Manual override → #{brand.raw_header}")
        end
      end

      if leuprolide_group?(group)
        return match_leuprolide(generic_name)
      end

      match_fuzzy(generic_name)
    end

    def self.extract_brand_candidate(generic_name)
      text = Text.collapse_ws(generic_name)
      if (m = text.match(/\(([^)]+)\)/))
        return { candidate: Text.collapse_ws(m[1]), parenthetical: true }
      end

      leading = text[/\A[[:alpha:]][[:alpha:]\-]*/]
      { candidate: Text.collapse_ws(leading), parenthetical: false }
    end

    def self.extract_month_number(text)
      m = text.to_s.match(/\b(\d+)\s*(?:month|mo)\b/i) || text.to_s.match(/\b(\d+)\s*-?\s*month/i)
      m&.[](1)&.to_i
    end

    def self.extract_leuprolide_family(text)
      hay = text.to_s
      return "Camcevi" if hay.match?(/camcevi/i)
      return "Eligard" if hay.match?(/eligard/i)
      return "Lupron" if hay.match?(/lupron/i)

      nil
    end

    private

    def override_for(group, generic_name)
      Config::BRAND_MATCH_OVERRIDES.each do |rule|
        next unless Text.sorted_token_key(rule[:group]) == Text.sorted_token_key(group)
        return rule[:master_header] if generic_name.to_s.match?(rule[:generic_name])
      end
      nil
    end

    def find_column_by_header(header_text)
      key = Text.exact_key(header_text)
      @columns.find { |col| Text.exact_key(col.raw_header) == key || Text.exact_key(col.core) == key } ||
        @columns.find { |col| Text.collapse_ws(col.raw_header).downcase.include?(header_text.downcase) } ||
        @columns.find { |col| Text.collapse_ws(col.core).downcase.include?(header_text.downcase) }
    end

    def leuprolide_group?(group)
      Text.sorted_token_key(group) == Text.sorted_token_key("LEUPROLIDE ACETATE") ||
        Text.tokens(group).include?("LEUPROLIDE")
    end

    def match_leuprolide(generic_name)
      family = self.class.extract_leuprolide_family(generic_name)
      month = self.class.extract_month_number(generic_name)
      unless family && month
        return Match.new(method: "NO_MATCH", brand: nil, confidence: 0.0, notes: "Leuprolide family+month incomplete")
      end

      hits = @columns.select do |col|
        self.class.extract_leuprolide_family(col.core) == family &&
          self.class.extract_month_number(col.core) == month
      end

      if hits.one?
        col = hits.first
        return Match.new(method: "OK", brand: col, confidence: 1.0, notes: "Leuprolide #{family} #{month} Month")
      end

      Match.new(method: "NO_MATCH", brand: nil, confidence: 0.0, notes: "Leuprolide family+month did not uniquely match")
    end

    def match_fuzzy(generic_name)
      extracted = self.class.extract_brand_candidate(generic_name)
      candidate = extracted[:candidate]
      if Text.blank?(candidate)
        return Match.new(method: "NO_MATCH", brand: nil, confidence: 0.0, notes: "No brand candidate")
      end

      best_col, best_score = best_against(candidate)
      if !extracted[:parenthetical] && (best_score.nil? || best_score < Config::GENERIC_RETRY_THRESHOLD)
        retry_col, retry_score = best_against("#{candidate} Generic")
        if retry_score && (best_score.nil? || retry_score > best_score)
          best_col = retry_col
          best_score = retry_score
        end
      end

      best_score ||= 0.0
      if best_col && best_score >= Config::MATCH_ACCEPT_THRESHOLD
        return Match.new(method: "OK", brand: best_col, confidence: best_score, notes: "Fuzzy match on #{best_col.core}")
      end

      Match.new(
        method: "NO_MATCH",
        brand: nil,
        confidence: best_score,
        notes: "Best score #{format('%.3f', best_score)} below #{Config::MATCH_ACCEPT_THRESHOLD}"
      )
    end

    def best_against(candidate)
      best_col = nil
      best_score = nil
      @columns.each do |col|
        score = Text.similarity(candidate, col.core)
        next if best_score && score <= best_score

        best_col = col
        best_score = score
      end
      [best_col, best_score]
    end
  end
end
