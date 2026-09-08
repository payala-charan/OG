class RegexFallbackService
  TABLES = %w[
    students payors insurances ogs payor_preferences samples users
    payment_factors name_matches uploaded_files documents
  ]

  def self.extract_intent(text)
    return { "intent" => "unknown", "confidence" => 0.0 } if text.blank?
    lc = text.downcase

    # Detect table
    table = TABLES.find { |t| lc.include?(t.gsub("_", " ")) || lc.include?(t) }
    table_sym = table&.to_sym

    # Simple WHERE pattern
    if m = lc.match(/(where|with)\s+([a-z_]+)\s*(=|is|equals|:)\s*([a-z0-9_ ]+)/)
      col = m[2]
      val = m[4].strip
      return {
        "intent" => "select_filtered",
        "table" => table_sym,
        "filters" => [{ "column" => col, "op" => "=", "value" => val }],
        "confidence" => 0.55
      }
    end

    # Table alone -> select all
    if table_sym.present?
      return { "intent" => "select_all", "table" => table_sym, "confidence" => 0.5 }
    end

    { "intent" => "unknown", "confidence" => 0.0 }
  end
end
