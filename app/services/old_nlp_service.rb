class NlpService
  # Attempt to extract structured intent using deterministic rules
  # returns a hash in the same shape as LlmService.mock_extract_intent
  def self.extract_intent(text)
    return { "intent" => "unknown", "confidence" => 0.0 } if text.blank?
    lc = text.to_s.downcase

    # detect greetings
    return { "intent" => "greeting", "confidence" => 0.9 } if lc.match?(/\b(hello|hi|hey|good morning|good evening)\b/)

    # detect exit
    return { "intent" => "exit", "confidence" => 0.9 } if lc.match?(/\b(bye|exit|stop|quit)\b/)

    # detect 'show/list all X'
    if m = lc.match(/\b(show|list|display|give me|fetch)\b.*\b(students|payors|insurances|ogs|payor preferences|payor_preferences|samples|users|payment_factors|name_matches|uploaded_files|documents)\b/)
      return { "intent" => "select_all", "table" => LlmService.normalize_table_name(m[2]), "confidence" => 0.9 }
    end

    # detect numeric comparisons: 'cgpa above 8', 'age less than 30', 'cgpa > 8'
    if m = lc.match(/(?<col>[a-z_]+)\s*(?:is|=|equals|>|<|>=|<=|above|below|less than|greater than)?\s*(?<op>>=|<=|>|<|=|is|equals|above|below|less than|greater than)?\s*(?<val>-?\d+(\.\d+)?)/)
      col = m[:col]; val = m[:val].to_f
      op_token = (m[:op] || "=").to_s
      op = case op_token
           when "above", "greater than" then ">"
           when "below", "less than" then "<"
           when ">=", "<=", ">", "<", "=" then op_token
           when "is", "equals" then "="
           else "="
           end
      # Try to find models containing this column
      candidate_models = SchemaService.models_with_column(col)
      if candidate_models.one?
        table = candidate_models.first.name.downcase.to_sym
        return { "intent" => "select_filtered", "table" => table, "filters" => [{ "column" => col, "op" => op, "value" => val }], "confidence" => 0.85 }
      else
        return { "intent" => "select_filtered", "filters" => [{ "column" => col, "op" => op, "value" => val }], "confidence" => 0.6 }
      end
    end

    # detect 'column is value' textual filters 'branch is cse'
    if m = lc.match(/(?<col>[a-z_]+)\s*(?:is|equals|=|:)\s*(?<val>[a-z0-9_\- ]{1,80})/)
      col = m[:col]; val = m[:val].strip
      candidate_models = SchemaService.models_with_column(col)
      if candidate_models.one?
        table = candidate_models.first.name.downcase.to_sym
        return { "intent" => "select_filtered", "table" => table, "filters" => [{ "column" => col, "op" => "=", "value" => val }], "confidence" => 0.8 }
      else
        return { "intent" => "select_filtered", "filters" => [{ "column" => col, "op" => "=", "value" => val }], "confidence" => 0.6 }
      end
    end

    # entity search (short phrase)
    if text.split.size <= 4
      return { "intent" => "select_record", "entity" => text.strip, "confidence" => 0.5 }
    end

    { "intent" => "unknown", "confidence" => 0.0 }
  end
end
