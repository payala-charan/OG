class NlpService
  GREETINGS = %w[
    hello hi hey greetings goodmorning goodmorning goodafternoon goodevening
  ]

  FAREWELLS = [
    /bye/, /thank\s*you/, /thanks/, /ok\s*bye/, /stop/, /exit/, /quit/
  ]

  TABLE_KEYWORDS = {
    "students" => :students,
    "student"  => :students,
    "payors"   => :payors,
    "payor"    => :payors,
    "insurances" => :insurances,
    "insurance"  => :insurances,
    "users"      => :users,
    "samples"    => :samples,
    "ogs"        => :ogs,
    "payor preferences" => :payor_preferences,
    "payment factors"   => :payment_factors,
    "documents"         => :documents,
    "uploaded files"    => :uploaded_files
  }

  QUERY_SYNONYMS = [
    "show", "display", "list", "get", "fetch", "give", "give me",
    "find", "want", "need", "see", "retrieve"
  ]

  def self.extract_intent(text)
    return { "intent" => "unknown", "confidence" => 0.0 } if text.blank?
    lc = text.downcase

    # ------------------------- GREETINGS -------------------------
    return { "intent" => "greeting", "confidence" => 0.95 } if GREETINGS.any? { |g| lc.include?(g) }

    # ------------------------- FAREWELLS -------------------------
    return { "intent" => "exit", "confidence" => 0.95 } if FAREWELLS.any? { |p| lc.match?(p) }

    # ------------------------- TABLE DETECTION -------------------------
    table = TABLE_KEYWORDS.keys.find { |t| lc.include?(t) }
    table_sym = TABLE_KEYWORDS[table] if table.present?

    # ------------------------- SELECT ALL -------------------------
    if QUERY_SYNONYMS.any? { |q| lc.include?(q) } && table.present?
      return {
        "intent" => "select_all",
        "table" => table_sym,
        "confidence" => 0.9
      }
    end

    # ------------------------- NUMERIC FILTERS -------------------------
    if m = lc.match(/(?<col>[a-z_]+)\s*(>=|<=|>|<|=|above|below|greater than|less than)?\s*(?<val>\d+(\.\d+)?)/)
      column = m[:col]
      value = m[:val]
      op = case m[2]
           when "above", "greater than" then ">"
           when "below", "less than" then "<"
           else m[2] || "="
           end

      models = SchemaService.models_with_column(column)
      table_guess = models.one? ? models.first.name.downcase.to_sym : nil

      return {
        "intent" => "select_filtered",
        "table" => table_guess || table_sym,
        "filters" => [{ "column" => column, "op" => op, "value" => value }],
        "confidence" => 0.85
      }
    end

    # ------------------------- TEXT FILTERS -------------------------
    if m = lc.match(/(?<col>[a-z_]+)\s*(is|equals|=)\s*(?<val>[a-z0-9_ ]{1,60})/)
      col = m[:col]
      val = m[:val].strip

      models = SchemaService.models_with_column(col)
      table_guess = models.one? ? models.first.name.downcase.to_sym : nil

      return {
        "intent" => "select_filtered",
        "table" => table_guess || table_sym,
        "filters" => [{ "column" => col, "op" => "=", "value" => val }],
        "confidence" => 0.82
      }
    end

    # ------------------------- SHORT SEARCH -------------------------
    if text.split.size <= 4
      return {
        "intent" => "select_record",
        "entity" => text.strip,
        "confidence" => 0.6
      }
    end

    { "intent" => "unknown", "confidence" => 0.0 }
  end
end
