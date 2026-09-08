class RegexFallbackService
  # Returns intent-like hash or { "intent" => "unknown" }
  def self.extract_intent(text)
    return { "intent" => "unknown", "confidence" => 0.0 } if text.blank?
    lc = text.downcase

    # Try to find table name by presence of known table words
    table_keyword = %w[payors insurances ogs payor_preferences users samples payment_factors students name_matches uploaded_files documents].find { |w| lc.include?(w.gsub('_', ' ')) || lc.include?(w) }
    table = table_keyword if table_keyword

    # Try to capture simple "<table> where <col> is <value>"
    if m = lc.match(/(#{table_keyword})?.{0,30}?(?:where|with|whose)\s+([a-z_]+)\s*(?:is|=|equals|:)?\s*([a-z0-9_\- ]{1,80})/)
      maybe_table = m[1] || table
      col = m[2]; val = m[3].strip
      return { "intent" => "select_filtered", "table" => maybe_table.presence&.to_sym, "filters" => [{ "column" => col, "op" => "=", "value" => val }], "confidence" => 0.55 }
    end

    # If no filters but table keyword only: select_all
    return { "intent" => "select_all", "table" => table.to_sym, "confidence" => 0.5 } if table.present?

    # fallback unknown
    { "intent" => "unknown", "confidence" => 0.0 }
  end
end
