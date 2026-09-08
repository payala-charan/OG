class RankingRecordsController < ApplicationController
  require "json"

  def index
    @record = RankingRecord.where(user_id: current_user&.id).order(created_at: :desc).first
  end

  def new
  end

  def create
    file = params[:file]

    if file.blank?
      redirect_to new_ranking_record_path, alert: "Please upload a file"
      return
    end

    excel = Roo::Spreadsheet.open(file.path)

    preferences = load_preferences_for_ranking

    sheet_results = []
    debug_mismatches = []
    debug_cells = []

    excel.sheets.each do |sheet_name|
      sheet = excel.sheet(sheet_name)
      # debugger
      result = build_ranking_sheet_result(sheet, sheet_name.to_s, preferences, debug_mismatches, debug_cells)
      sheet_results << result if result
    end

    if sheet_results.empty?
      redirect_to new_ranking_record_path,
        alert: "No valid sheets found. Each sheet needs row 1 with 'Generic Name' in the first column and at least one payor column."
      return
    end

    final_data = {
      "sheets" => sheet_results,
      "debug_mismatches" => debug_mismatches,
      "debug_cells" => debug_cells,
      "debug_generated_at" => Time.current.iso8601
    }

    RankingRecord.where(user_id: current_user.id).delete_all

    record = RankingRecord.create!(
      data: final_data,
      user_id: current_user.id,
      user_email: current_user.email
    )

    redirect_to ranking_record_path(record)
  end

  def show
    @record = RankingRecord.find(params[:id])
    @sheet_sections = @record.sheet_sections
    @debug_mismatches = Array(@record.data&.dig("debug_mismatches"))
    @debug_cells = Array(@record.data&.dig("debug_cells"))
  end

  # Frontend debug helper:
  # generic_name_group + payor -> raw/parsed insurances from PayorPreference.
  def lookup_insurances
    group = params[:generic_name_group].to_s.upcase.strip
    payor = normalize(params[:payor])
    period = params[:accounting_period_id].presence || 5

    records = PayorPreference.where(
      generic_name_group: group,
      accounting_period_id: period,
      payor: payor
    )

    raw = records.pluck(:insurances).compact.uniq
    parsed = raw.flat_map { |v| parse_insurance_names(v) }.uniq

    render json: {
      generic_name_group: group,
      payor: payor,
      accounting_period_id: period.to_i,
      found_records: records.size,
      raw_insurances: raw,
      parsed_insurances: parsed
    }
  end

  private

  def build_ranking_sheet_result(sheet, sheet_name, preferences, debug_mismatches, debug_cells)
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
    # debugger
    # payor_data = payors.each_with_index.map do |payor, index|
    #   records, matched_payor = find_preference_records(preferences, sheet_generic_group, normalized_payors[index])
    #   db_insurances = records.flat_map { |rec| parse_insurance_names(rec.insurances) }.uniq
    #   { db_insurances: db_insurances, matched_payor: matched_payor }
    # end
    # payor_data = payors.each_with_index.map do |payor, index|
    #   normalized_payor = normalized_payors[index]

    #   records, _matched_payor = find_preference_records(
    #     preferences,
    #     sheet_generic_group,
    #     normalized_payor
    #   )

    #   db_insurances = records.flat_map do |rec|
    #     begin
    #       parse_insurance_names(rec.insurances)
    #     rescue => e
    #       puts "Error parsing insurance for #{payor}: #{e.message}"
    #       []
    #     end
    #   end.uniq

    #   {
    #     db_insurances: db_insurances,
    #     matched_payor: payor.to_s.downcase.strip
    #   }
    # end

    # payor_data = payors.each_with_index.map do |payor, index|
    #   normalized_payor = normalized_payors[index]

    #   records, _matched_payor = find_preference_records(
    #     preferences,
    #     sheet_generic_group,
    #     normalized_payor
    #   )

    #   db_insurances = records
    #                     .flat_map { |rec| parse_insance_names(rec.insurances) rescue [] }
    #                     .uniq

    #   {
    #     db_insurances: db_insurances,
    #     matched_payor: payor.to_s.downcase.strip   # ✅ FIX: use actual payor
    #   }
    # end

    payor_data = payors.map do |payor|
      normalized_payor = payor.to_s.downcase.strip

      records = PayorPreference.where(
        generic_name_group: sheet_generic_group,
        payor: normalized_payor
      )

      db_insurances = records.flat_map do |rec|
        begin
          JSON.parse(rec.insurances)
        rescue
          []
        end
      end.uniq

      {
        db_insurances: db_insurances,
        matched_payor: normalized_payor
      }
    end

    (2..sheet.last_row).each do |i|
      # debugger
      row = sheet.row(i)  
      next if row.compact.blank?

      row_data = Hash[[headers, row].transpose]

      generic_name = row_data["Generic Name"]
      next if generic_name.blank?
      
      generic_group = sheet_generic_group
      brand_token = brand_token_for(generic_name, generic_group)

      cells = payors.each_with_index.map do |payor, index|
        normalized_payor = normalized_payors[index]
        matched_payor = payor_data[index][:matched_payor]
        db_insurances = payor_data[index][:db_insurances]

        raw_actual = row_data[payor]
        actual =
          if raw_actual.nil? || (raw_actual.is_a?(String) && raw_actual.strip.blank?)
            "X"
          else
            raw_actual.is_a?(Numeric) ? raw_actual : raw_actual.to_s.strip
          end

        should_rank = should_have_numeric_rank?(db_insurances, brand_token)
        has_rank = actual_has_numeric_rank?(actual)

        expected = should_rank ? "✔" : "X"

        status =
          if should_rank && has_rank
            "success"
          elsif !should_rank && !has_rank
            "success"
          else
            "failure"
          end

        reason =
          if should_rank && has_rank
            "Brand is allowed for payor and cell has numeric rank."
          elsif !should_rank && !has_rank
            "Brand is not allowed for payor and cell correctly has X."
          elsif should_rank && !has_rank
            "Brand is allowed for payor but cell has X/non-numeric value."
          else
            "Brand is not allowed for payor but cell has numeric rank."
          end

        debug_cells << {
          "sheet_name" => sheet_name,
          "row_number" => i,
          "generic_name" => generic_name,
          "generic_group" => generic_group,
          "brand_token" => brand_token,
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
      permitted_classes: [Array, String],
      permitted_symbols: [],
      aliases: true
    )
    case obj
    when Array
      obj.flat_map { |x| parse_insurance_raw_inner(x) }
    when String
      return [obj] if obj.strip == s.strip

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

  def find_preference_records(preferences, generic_group, normalized_payor)
    g = generic_group.to_s.upcase.strip
    np = normalize(normalized_payor)

    hit = preferences[[g, np]]
    return [hit, np] if hit.present?

    preferences.each do |(grp, pay), recs|
      g2 = grp.to_s.upcase.strip
      next unless g2 == g
      next if pay.blank?

      p2 = normalize(pay)
      next if p2.blank?
      return [recs, p2] if p2 == np

      next if np.length < 8 || p2.length < 8

      return [recs, p2] if p2.include?(np) || np.include?(p2)
    end

    [[], np]
  end

  def load_preferences_for_ranking
    PayorPreference
      .where(accounting_period_id: 5)
      .group_by { |p| [p.generic_name_group.to_s.upcase.strip, normalize(p.payor)] }
  end

  # def normalize(value)
  #   value.to_s.gsub(/\u00A0/, " ").strip.downcase.squeeze(" ")
  # end
  def normalize(str)
    str.to_s.downcase.strip
  end

  def extract_generic_group(generic_name)
    return "" if generic_name.blank?
    cleaned = generic_name.to_s.strip
    # Step 1: Remove brand part (anything inside parentheses)
    cleaned = cleaned.split("(").first
    # Step 2: Remove extra spaces
    cleaned = cleaned.strip
    # Step 3: Remove biosimilar suffix (only from last word)
    words = cleaned.split(/\s+/)
    words = words.map do |word|
      word.include?("-") ? word.split("-").first : word
    end
    # Step 4: Join back full generic name
    final_generic = words.join(" ")
    final_generic.upcase
  end
end
