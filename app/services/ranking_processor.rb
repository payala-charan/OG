class RankingProcessor
  def initialize(file:, team_id:, period_id:, user: nil, is_auto: false)
    @file = file
    @team_id = team_id || "198"
    @period_id = period_id || "6"
    @user = user
    @is_auto = is_auto
  end

  def call
    excel = Roo::Spreadsheet.open(@file.path)
    # debugger
    preferences = load_preferences_for_ranking(@period_id)

    sheet_results = []
    debug_mismatches = []
    debug_cells = []

    excel.sheets.each do |sheet_name|
      sheet = excel.sheet(sheet_name)
      result = build_ranking_sheet_result(sheet, sheet_name.to_s, preferences, debug_mismatches, debug_cells, @team_id, @period_id)
      sheet_results << result if result
    end

    if sheet_results.empty?
      return { success: false, error: "No valid sheets found. Each sheet needs row 1 with 'Generic Name' in the first column and at least one payor column." }
    end

    final_data = {
      "sheets" => sheet_results,
      "debug_mismatches" => debug_mismatches,
      "debug_cells" => debug_cells,
      "debug_generated_at" => Time.current.iso8601
    }

    if @is_auto
      record = AutoRankingRecord.create!(
        data: final_data,
        file: @file.original_filename,
        user_id: @user&.id,
      )
    else
      RankingRecord.where(user_id: @user.id).delete_all if @user
      record = RankingRecord.create!(
        data: final_data,
        user_id: @user&.id,
        user_email: @user&.email
      )
    end

    { success: true, record: record }
  end

  private

  def build_ranking_sheet_result(sheet, sheet_name, preferences, debug_mismatches, debug_cells, team_id, period_id)
    # debugger
    return nil if sheet.last_row.nil? || sheet.last_row < 2

    headers = sheet.row(1).map { |h| h.to_s.strip }
    return nil unless headers.include?("Generic Name")

    payors = headers[1..]
    return nil if payors.blank?

    normalized_payors = payors.map { |p| normalize(p) }
    structured_rows = []

    generic_name_index = headers.index("Generic Name")
    generic_names = (2..sheet.last_row).map { |i| sheet.row(i)[generic_name_index].to_s.strip }.reject(&:blank?)
    return nil if generic_names.empty?

    name_for_group = generic_names.find { |n| n.include?("(") } || generic_names.first
    sheet_generic_group = extract_generic_group(name_for_group)

    payor_data = payors.map do |payor|
      normalized_payor = payor.to_s.downcase.strip

      records = PayorPreference.where(
        team_id: team_id,
        generic_name_group: sheet_generic_group,
        payor: normalized_payor,
        accounting_period_id: period_id
      )

      db_insurances = records.flat_map do |rec|
        begin
          JSON.parse(rec.insurances)
        rescue
          []
        end
      end.uniq

      # Unidentified payor: no PayorPreference insurances, so rank every
      # brand for this generic_name_group from BSP (same CMS ranking as known payors).
      if db_insurances.blank?
        db_insurances = group_insurances_from_bsp(team_id, period_id, sheet_generic_group)
      end

      # CALCULATE RANKS VIA CMS COST (HIGHEST = 1)
      prices = NewBiosimilarPrice.where(
        team_id: team_id,
        accounting_period_id: period_id,
        generic_name_group: sheet_generic_group,
        extracted_brand_name: db_insurances.map(&:upcase)
      ).pluck(:extracted_brand_name, :extracted_strength, :blended_cms_margin_three_forty_b_cost)

      valid_prices = prices.reject { |p| p[2].nil? }.sort_by { |p| -p[2].to_f }

      payor_ranks = {}
      current_rank = 0
      last_cost = nil
      valid_prices.each do |p|
        brand = p[0].to_s.downcase
        str = p[1].to_s.upcase
        cost = p[2].to_f

        if last_cost != cost
          current_rank += 1
          last_cost = cost
        end
        payor_ranks[[ brand, str ]] = current_rank
      end

      {
        db_insurances: db_insurances,
        matched_payor: normalized_payor,
        payor_ranks: payor_ranks
      }
    end

    (2..sheet.last_row).each do |i|
      # debugger
      row = sheet.row(i)
      next if row.compact.blank?

      row_data = Hash[[ headers, row ].transpose]

      generic_name = row_data["Generic Name"]
      next if generic_name.blank?

      generic_group = sheet_generic_group
      brand_token = brand_token_for(generic_name, generic_group).downcase
      extracted_str = extract_strength(generic_name)

      cells = payors.each_with_index.map do |payor, index|
        # debugger
        normalized_payor = normalized_payors[index]
        matched_payor = payor_data[index][:matched_payor]
        db_insurances = payor_data[index][:db_insurances]
        payor_ranks = payor_data[index][:payor_ranks]

        raw_actual = row_data[payor]
        # debugger
        actual =
          if raw_actual.nil? || (raw_actual.is_a?(String) && raw_actual.strip.blank?)
            "X"
          else
            raw_actual.is_a?(Numeric) ? (raw_actual.to_f == raw_actual.to_i ? raw_actual.to_i.to_s : raw_actual.to_s) : raw_actual.to_s.strip
          end

        should_rank = should_have_numeric_rank?(db_insurances, brand_token)
        has_rank = actual_has_numeric_rank?(actual)

        calculated_rank = payor_ranks[[ brand_token, extracted_str ]]

        if should_rank
          if calculated_rank
            expected = calculated_rank.to_s
            if actual == expected
              status = "success"
              reason = "Rank matched exactly: Expected #{expected}"
            else
              status = "failure"
              reason = "Mismatch: Expected Rank #{expected}, got #{actual}"
            end
          else
            expected = "✔"
            if has_rank
              status = "success"
              reason = "Brand allowed and numeric value provided. (No CMS Pricing baseline found to verify exact rank number)"
            else
              status = "failure"
              reason = "Brand allowed but cell has missing or invalid numeric rank. (No baselines found)"
            end
          end
        else
          expected = "X"
          if !has_rank
            status = "success"
            reason = "Brand not allowed, successfully labeled X/Empty."
          else
            status = "failure"
            reason = "Brand not allowed but cell oddly contains a numeric rank."
          end
        end

        debug_cells << {
          "sheet_name" => sheet_name,
          "row_number" => i,
          "generic_name" => generic_name,
          "generic_group" => generic_group,
          "brand_token" => brand_token,
          "strength_token" => extracted_str,
          "payor_header" => payor.to_s,
          "payor_lookup" => matched_payor,
          "actual" => actual,
          "expected" => expected,
          "status" => status,
          "reason" => reason,
          "has_rank" => has_rank,
          "should_rank" => should_rank,
          "allowed_insurances" => db_insurances
        }

        if status == "failure"
          debug_mismatches << {
            "sheet_name" => sheet_name,
            "row_number" => i,
            "generic_name" => generic_name,
            "generic_group" => generic_group,
            "brand_token" => brand_token,
            "strength_token" => extracted_str,
            "payor_header" => payor.to_s,
            "payor_lookup" => matched_payor,
            "actual" => actual,
            "expected" => expected,
            "has_rank" => has_rank,
            "should_rank" => should_rank,
            "allowed_insurances" => db_insurances
          }
        end

        {
          "actual" => actual,
          "expected" => expected,
          "status" => status,
          "debug" => {
            "generic_group" => generic_group,
            "brand_token" => brand_token,
            "payor_lookup" => matched_payor,
            "allowed_insurances" => db_insurances,
            "has_rank" => has_rank,
            "should_rank" => should_rank
          }
        }
      end

      structured_rows << {
        "generic_name" => generic_name,
        "cells" => cells
      }
    end

    return nil if structured_rows.empty?

    {
      "sheet_name" => sheet_name,
      "headers" => payors.map(&:to_s),
      "rows" => structured_rows
    }
  end

  def should_have_numeric_rank?(db_insurances, brand_token)
    return false if db_insurances.blank? || brand_token.blank?
    db_insurances.include?(brand_token)
  end

  def group_insurances_from_bsp(team_id, period_id, generic_group)
    return [] if generic_group.blank?

    NewBiosimilarPrice.where(
      team_id: team_id,
      accounting_period_id: period_id,
      generic_name_group: generic_group
    ).pluck(:extracted_brand_name).compact.map { |n| n.to_s.downcase.strip }.reject(&:blank?).uniq
  rescue
    []
  end

  def brand_token_for(generic_name, generic_group)
    m = generic_name.to_s.match(/\(([^)]+)\)/)
    if m
      inner = m[1].to_s.strip
      return normalize(inner) if inner.present?
    end
    normalize(generic_group)
  end

  def actual_has_numeric_rank?(actual)
    return false if actual.nil?
    return true if actual.is_a?(Numeric) && !actual.is_a?(TrueClass) && !actual.is_a?(FalseClass)

    s = actual.to_s.gsub(/\u00A0/, " ").strip
    return false if s.blank?
    return false if s.match?(/\AX\z/i)

    v = Float(s)
    v.finite?
  rescue ArgumentError, TypeError
    false
  end

  def parse_insurance_names(raw)
    inner = parse_insurance_raw_inner(raw)
    inner.map { |n| normalize(n) }.reject(&:blank?).uniq
  end

  def parse_insurance_raw_inner(raw)
    case raw
    when nil
      []
    when Array
      raw.flat_map { |x| parse_insurance_raw_inner(x) }
    when String
      s = raw.strip
      return [] if s.blank?

      begin
        parsed = JSON.parse(s)
        parse_insurance_raw_inner(parsed)
      rescue JSON::ParserError, TypeError
        parse_insurance_non_json_string(s)
      end
    else
      parse_insurance_raw_inner(raw.to_s)
    end
  end

  def parse_insurance_non_json_string(s)
    obj = Psych.safe_load(
      s,
      permitted_classes: [ Array, String ],
      permitted_symbols: [],
      aliases: true
    )
    case obj
    when Array
      obj.flat_map { |x| parse_insurance_raw_inner(x) }
    when String
      return [ obj ] if obj.strip == s.strip
      parse_insurance_raw_inner(obj)
    else
      comma_split_insurance_names(s)
    end
  rescue Psych::Exception, TypeError, ArgumentError
    comma_split_insurance_names(s)
  end

  def comma_split_insurance_names(s)
    cleaned = s.delete_prefix("[").delete_suffix("]").tr('"', "").tr("'", "")
    cleaned.split(/[,|]/).map(&:strip).reject(&:blank?)
  end

  def load_preferences_for_ranking(period_id)
    PayorPreference
      .where(accounting_period_id: period_id, team_id: @team_id)
      .group_by { |p| [ p.generic_name_group.to_s.upcase.strip, normalize(p.payor) ] }
  end

  def normalize(str)
    str.to_s.downcase.strip
  end

  def extract_generic_group(generic_name)
    return "" if generic_name.blank?
    cleaned = generic_name.to_s.strip
    cleaned = cleaned.split("(").first
    cleaned = cleaned.strip
    words = cleaned.split(/\s+/)
    words = words.map do |word|
      word.include?("-") ? word.split("-").first : word
    end
    final_generic = words.join(" ")
    final_generic.upcase
  end

  def extract_strength(generic_name)
    generic = generic_name.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
                          .gsub(/\u00A0/, " ")
                          .gsub(/[\r\n\t]/, " ")
                          .gsub(/\s+/, " ")
                          .strip
                          .downcase
                          .gsub(/\s*\/\s*/, "/")
                          .gsub(/\s*(mg|mcg|g|ml)\b/, '\1')

    strength = generic[/\d+(?:\.\d+)?(?:mg|mcg|g)\/\d+(?:\.\d+)?ml/] ||
               generic[/\d+(?:\.\d+)?(?:mg|mcg|g)\/ml/] ||
               generic[/\d+(?:\.\d+)?(?:mg|mcg|g|ml)/] ||
               generic.scan(/\d+(?:\.\d+)?[a-zA-Z]+/).first

    strength&.upcase
  end
end
