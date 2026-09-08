require "bigdecimal"
require "roo"

class TallyValidationService
  class ValidationError < StandardError; end

  GROUPING_COLUMNS = [
    "GENERIC NAME",
    "FINANCIAL CLASS",
    "PRIMARY PAYOR NAME",
    # "BENEFIT PLAN NAME",
    "HCPCS CODE",
    # "NDC CODE",
    "CHARGE CLASS",
    "PACKAGE SIZE"
  ].freeze

  SUMMATION_COLUMNS = [
    "TOTAL UNITS",
    "CMS TOTAL UNITS",
    "TOTAL PRODUCT COST",
    "TOTAL INSURANCE PAYMENT",
    "ACTUAL REIMBURSEMENT",
    "TOTAL MARGIN",
    "CONVERSION TOTAL PRODUCT COST",
    "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT",
    "CONVERSION PRODUCT TOTAL MARGIN",
    "BLENDED CONVERSION TOTAL PRODUCT COST",
    "BLENDED CONVERSION TOTAL MARGIN",
    "BLENDED CONVERSION COST DIFFERENCE",
    "BLENDED CONVERSION MARGIN DIFFERENCE"
  ].freeze

  COST_COLUMNS = [
    "PRODUCT COST PER UNIT",
    "CONVERSION PRODUCT COST PER UNIT"
  ].freeze

  PERCENTAGE_COLUMNS = [
    "PERCENT MARGIN",
    "CONVERSION PRODUCT PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
  ].freeze

  REQUIRED_COLUMNS = (GROUPING_COLUMNS + SUMMATION_COLUMNS + COST_COLUMNS + PERCENTAGE_COLUMNS).freeze
  PASS_TOLERANCE = 0.01
  PARTIAL_RADIUS = 5.0

  def initialize(individual_file_path, grouped_file_path)
    @individual_file_path = individual_file_path
    @grouped_file_path = grouped_file_path
  end

  def call
    # 1. Open Spreadsheets
    begin
      indiv_spreadsheet = Roo::Spreadsheet.open(@individual_file_path)
      grp_spreadsheet = Roo::Spreadsheet.open(@grouped_file_path)
    rescue => e
      raise ValidationError, "Unable to validate the uploaded files. Please check that both files are valid Excel sheets."
    end

    # 2. Check Headers
    indiv_headers = indiv_spreadsheet.row(1).map(&:to_s).map(&:strip)
    grp_headers = grp_spreadsheet.row(1).map(&:to_s).map(&:strip)

    verify_required_headers!(indiv_headers, "Individual")
    verify_required_headers!(grp_headers, "Grouped")

    # 3. Index Individual rows by grouping combination so each Grouped row can look them up.
    individual_records_by_key = {}
    each_data_row(indiv_spreadsheet, indiv_headers) do |row_data|
      key = generate_group_key(row_data)
      individual_records_by_key[key] ||= []
      individual_records_by_key[key] << row_data
    end

    # 4. Grouped sheet is primary: every Grouped record is validated in sheet order.
    #    Individual-only combinations are not reported.
    validated_rows = []
    each_data_row(grp_spreadsheet, grp_headers) do |grp_row|
      key = generate_group_key(grp_row)
      indiv_rows = individual_records_by_key[key] || []
      grouping_keys = grouping_keys_from(grp_row)

      validated_rows << if indiv_rows.empty?
                          build_unexpected_grouped_result(grouping_keys, grp_row)
                        else
                          validate_single_group(grouping_keys, grp_row, indiv_rows)
                        end
    end

    {
      validated_rows: validated_rows
    }
  end

  private

  def verify_required_headers!(headers, file_label)
    REQUIRED_COLUMNS.each do |col|
      if find_header_index(headers, col).nil?
        raise ValidationError, "#{file_label} file is missing required column: #{col}"
      end
    end
  end

  def find_header_index(headers, target)
    headers.find_index do |h|
      h_str = h.to_s.strip.downcase.gsub(/[\s_]/, "")
      t_str = target.to_s.strip.downcase.gsub(/[\s_]/, "")
      h_str == t_str
    end
  end

  def normalize_header_name(header)
    header.to_s.strip.upcase.tr("_", " ").gsub(/\s+/, " ")
  end

  def extract_row_data(row, headers)
    data = {}
    headers.each_with_index do |header, idx|
      next if header.nil? || header.to_s.strip.empty?
      data[normalize_header_name(header)] = row[idx]
    end
    data
  end

  def row_value(row_data, col)
    row_data[normalize_header_name(col)]
  end

  def each_data_row(spreadsheet, headers)
    last = spreadsheet.last_row
    return if last.nil? || last < 2

    end_row = last
    if last > 2
      last_data = extract_row_data(spreadsheet.row(last), headers)
      end_row = last - 1 if totals_row?(last_data)
    end

    (2..end_row).each do |i|
      row = spreadsheet.row(i)
      next if row.all?(&:nil?)

      row_data = extract_row_data(row, headers)
      next if grouping_blank?(row_data)

      yield row_data
    end
  end

  def grouping_blank?(row_data)
    GROUPING_COLUMNS.all? { |col| row_value(row_data, col).to_s.strip.empty? }
  end

  def totals_row?(row_data)
    return true if grouping_blank?(row_data)

    (GROUPING_COLUMNS + ["HOSPITAL NAME", "ORDER NAME"]).any? do |col|
      row_value(row_data, col).to_s.strip.match?(/\A(grand\s*)?totals?\z/i)
    end
  end

  def grouping_keys_from(row_data)
    GROUPING_COLUMNS.each_with_object({}) do |col, h|
      raw = row_value(row_data, col)
      h[col] = case col
               # when "NDC CODE" then normalize_ndc_code(raw)
               when "PACKAGE SIZE" then normalize_package_size(raw)
               else raw.to_s.strip
               end
    end
  end

  def generate_group_key(row_data)
    [
      normalize_text(row_value(row_data, "GENERIC NAME")),
      normalize_text(row_value(row_data, "FINANCIAL CLASS")),
      normalize_text(row_value(row_data, "PRIMARY PAYOR NAME")),
      # normalize_text(row_value(row_data, "BENEFIT PLAN NAME")),
      normalize_text(row_value(row_data, "HCPCS CODE")),
      # normalize_ndc_for_grouping(row_value(row_data, "NDC CODE")),
      normalize_charge_class(row_value(row_data, "CHARGE CLASS")),
      normalize_package_size(row_value(row_data, "PACKAGE SIZE"))
    ].join("||")
  end

  def normalize_text(val)
    val.to_s.strip.upcase.gsub(/\s+/, " ")
  end

  def normalize_package_size(val)
    return "" if val.nil?

    str = val.to_s.strip
    return "" if str.empty?

    num = Float(str) rescue nil
    if num && num == num.to_i
      num.to_i.to_s
    else
      str.upcase.gsub(/\s+/, " ")
    end
  end

  def normalize_ndc_code(raw_ndc)
    return "" if raw_ndc.nil?

    digits = if raw_ndc.is_a?(Numeric)
               raw_ndc.to_i.to_s
             else
               str = raw_ndc.to_s.strip
               return "" if str.empty?

               if str.match?(/\A-?\d+(\.\d+)?e[+-]?\d+\z/i)
                 str.to_f.to_i.to_s
               else
                 str.gsub(/\D/, "")
               end
             end

    return "" if digits.empty?

    digits = digits[-11..] if digits.length > 11
    digits.length < 11 ? digits.rjust(11, "0") : digits
  end

  # 11-digit NDC is labeler(5) + product(4) + package(2). Source files often
  # disagree on the package digits (55513020701 vs 55513020721) for the same
  # product; package size is already its own grouping column.
  def normalize_ndc_for_grouping(raw_ndc)
    digits = normalize_ndc_code(raw_ndc)
    return "" if digits.empty?

    digits.length >= 9 ? digits[0, 9] : digits
  end

  def normalize_charge_class(charge_class)
    cc = charge_class.to_s.strip.upcase
    if cc == "EMERGENCY" || cc == "OUTPATIENT"
      "OUTPATIENT"
    else
      cc
    end
  end

  def parse_big_decimal(val)
    return BigDecimal("0") if val.nil?
    return val if val.is_a?(BigDecimal)

    if val.is_a?(Numeric)
      return BigDecimal(val.to_s)
    end

    str = val.to_s.strip
    return BigDecimal("0") if str.empty?

    # Accounting negatives are written as (12.1%) / ($12.10). A leading minus
    # must be left on the number — flipping again would drop the sign.
    accounting_negative = str.start_with?("(") && str.end_with?(")")
    cleaned_str = str.gsub(/[\$,()%]/, "").strip
    return BigDecimal("0") if cleaned_str.empty?

    cleaned_val = begin
      BigDecimal(cleaned_str)
    rescue ArgumentError
      BigDecimal("0")
    end

    accounting_negative ? -cleaned_val.abs : cleaned_val
  end

  # Helper to compare expected and actual BigDecimal values
  def compare_values(expected, actual, is_percentage: false)
    if expected.nil?
      return { expected: nil, actual: actual.to_f, status: "not_calculable" }
    end

    expected_fd = expected.to_f
    actual_fd = actual.to_f

    # 1) Direct tolerance check
    if (actual_fd - expected_fd).abs < PASS_TOLERANCE
      return comparison_result(expected_fd, actual_fd, "passed")
    end

    # 2) Try rounding the expected value and compare
    precision = is_percentage ? (expected_fd.abs >= 100 ? 1 : 2) : 2
    rounded_expected = expected_fd.round(precision)
    if (actual_fd - rounded_expected).abs < PASS_TOLERANCE
      return comparison_result(rounded_expected, actual_fd, "passed")
    end

    # 2b) Percentage columns in grouped sheets are typically 1 decimal
    # (98.1%, -12.1%). Treat matching 1-decimal rounding as a pass.
    if is_percentage && (actual_fd.round(1) - expected_fd.round(1)).abs < PASS_TOLERANCE
      return comparison_result(expected_fd, actual_fd, "passed")
    end

    # 3) Partial: actual must lie within expected ± 5 (e.g. 50.05 => 45.05..55.05),
    # using the unrounded expected — not a 50.00..60.00 window.
    if actual_fd >= (expected_fd - PARTIAL_RADIUS) && actual_fd <= (expected_fd + PARTIAL_RADIUS)
      return comparison_result(expected_fd, actual_fd, "partial")
    end

    # 4) For percentage columns only: try scaling expected down by 100 and rounding
    if is_percentage
      scaled = expected_fd / 100.0
      scaled_rounded = scaled.round(2)
      if (actual_fd - scaled_rounded).abs < PASS_TOLERANCE
        return comparison_result(scaled_rounded, actual_fd, "passed")
      end
    end

    # 5) Final: failed
    comparison_result(expected_fd, actual_fd, "failed")
  end

  def comparison_result(expected_fd, actual_fd, status)
    {
      expected: expected_fd.round(4),
      actual: actual_fd.round(4),
      diff: (actual_fd - expected_fd).round(4),
      status: status
    }
  end

  # Reconciled validation case
  def validate_single_group(grouping_keys, grp_row, indiv_rows)
    column_validations = {}
    row_has_failed = false
    row_has_partial = false

    # 1. Validate Summation Columns
    SUMMATION_COLUMNS.each do |col|
      expected = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }.sum
      actual = parse_big_decimal(row_value(grp_row, col))
      res = compare_values(expected, actual)
      column_validations[col] = res
      row_has_failed ||= (res[:status] == "failed")
      row_has_partial ||= (res[:status] == "partial")
    end

    # 2. Validate Cost Columns
    COST_COLUMNS.each do |col|
      indiv_costs = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }
      first_cost = indiv_costs.first || BigDecimal("0")
      consistent = indiv_costs.all? { |c| (c - first_cost).abs < BigDecimal("0.01") }

      if consistent
        actual = parse_big_decimal(row_value(grp_row, col))
        res = compare_values(first_cost, actual)
        column_validations[col] = res
          row_has_failed ||= (res[:status] == "failed")
          row_has_partial ||= (res[:status] == "partial")
      else
        column_validations[col] = {
          expected: "Inconsistent",
          actual: parse_big_decimal(row_value(grp_row, col)).to_f,
          status: "failed",
          message: "Individual group values are inconsistent"
        }
        row_has_failed = true
      end
    end

    # 3. Validate Percentage Columns
    percentages_expected = calculate_grouped_percentages(grp_row)
    PERCENTAGE_COLUMNS.each do |col|
      expected = percentages_expected[col]
      if expected.nil?
        column_validations[col] = {
          expected: "Not Calculable",
          actual: parse_big_decimal(row_value(grp_row, col)).to_f,
          status: "warning",
          message: "Denominator is zero or missing"
        }
      else
        actual = parse_big_decimal(row_value(grp_row, col))
        res = compare_values(expected, actual, is_percentage: true)
        column_validations[col] = res
        row_has_failed ||= (res[:status] == "failed")
        row_has_partial ||= (res[:status] == "partial")
      end
    end

    {
      type: "matched_group",
      keys: grouping_keys,
      grouped_row_data: grp_row,
      individual_records: indiv_rows,
      columns: column_validations,
      status: row_has_failed ? "mismatch" : (row_has_partial ? "partial" : "match")
    }
  end

  # Helper to calculate percentages from Grouped row values
  def calculate_grouped_percentages(grp_row)
    total_margin = parse_big_decimal(row_value(grp_row, "TOTAL MARGIN"))
    total_product_cost = parse_big_decimal(row_value(grp_row, "TOTAL PRODUCT COST"))

    conv_total_margin = parse_big_decimal(row_value(grp_row, "CONVERSION PRODUCT TOTAL MARGIN"))
    conv_total_cost = parse_big_decimal(row_value(grp_row, "CONVERSION TOTAL PRODUCT COST"))

    blended_total_margin = parse_big_decimal(row_value(grp_row, "BLENDED CONVERSION TOTAL MARGIN"))
    blended_total_cost = parse_big_decimal(row_value(grp_row, "BLENDED CONVERSION TOTAL PRODUCT COST"))

    # Formula: PERCENT MARGIN
    percent_margin = if total_product_cost.zero?
                       nil
    else
                       (total_margin / total_product_cost) * 100
    end

    # Formula: CONVERSION PRODUCT PERCENT MARGIN
    conv_percent_margin = if conv_total_cost.zero?
                            nil
    else
                            (conv_total_margin / conv_total_cost) * 100
    end

    # Formula: BLENDED CONVERSION PERCENT MARGIN
    blended_percent_margin = if blended_total_cost.zero?
                               nil
    else
                               (blended_total_margin / blended_total_cost) * 100
    end

    # Formula: BLENDED CONVERSION PERCENT MARGIN DIFFERENCE
    blended_diff = if blended_percent_margin.nil? || percent_margin.nil?
                     nil
    else
                     blended_percent_margin - percent_margin
    end

    {
      "PERCENT MARGIN" => percent_margin,
      "CONVERSION PRODUCT PERCENT MARGIN" => conv_percent_margin,
      "BLENDED CONVERSION PERCENT MARGIN" => blended_percent_margin,
      "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE" => blended_diff
    }
  end

  def build_missing_grouped_result(grouping_keys, indiv_rows)
    column_validations = {}
    SUMMATION_COLUMNS.each do |col|
      expected = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }.sum
      column_validations[col] = {
        expected: expected.to_f,
        actual: nil,
        status: "failed",
        message: "Missing Grouped record"
      }
    end

    COST_COLUMNS.each do |col|
      indiv_costs = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }
      first_cost = indiv_costs.first || BigDecimal("0")
      consistent = indiv_costs.all? { |c| (c - first_cost).abs < BigDecimal("0.01") }
      column_validations[col] = {
        expected: consistent ? first_cost.to_f : "Inconsistent",
        actual: nil,
        status: "failed",
        message: "Missing Grouped record"
      }
    end

    PERCENTAGE_COLUMNS.each do |col|
      column_validations[col] = {
        expected: "Not Calculable",
        actual: nil,
        status: "failed",
        message: "Missing Grouped record"
      }
    end

    {
      type: "only_in_individual",
      keys: grouping_keys,
      grouped_row_data: {},
      individual_records: indiv_rows,
      columns: column_validations,
      status: "mismatch",
      message: "Missing Grouped record"
    }
  end

  def build_unexpected_grouped_result(grouping_keys, grp_row)
    column_validations = {}
    SUMMATION_COLUMNS.each do |col|
      column_validations[col] = {
        expected: nil,
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Unexpected Grouped record"
      }
    end

    COST_COLUMNS.each do |col|
      column_validations[col] = {
        expected: nil,
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Unexpected Grouped record"
      }
    end

    PERCENTAGE_COLUMNS.each do |col|
      column_validations[col] = {
        expected: nil,
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Unexpected Grouped record"
      }
    end

    {
      type: "only_in_grouped",
      keys: grouping_keys,
      grouped_row_data: grp_row,
      individual_records: [],
      columns: column_validations,
      status: "mismatch",
      message: "Unexpected Grouped record (no matching Individual records)"
    }
  end

  def build_duplicate_grouped_result(grouping_keys, grp_row, indiv_rows, count)
    column_validations = {}
    SUMMATION_COLUMNS.each do |col|
      expected = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }.sum
      column_validations[col] = {
        expected: expected.to_f,
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Duplicate Grouped record"
      }
    end

    COST_COLUMNS.each do |col|
      indiv_costs = indiv_rows.map { |r| parse_big_decimal(row_value(r, col)) }
      first_cost = indiv_costs.first || BigDecimal("0")
      consistent = indiv_costs.all? { |c| (c - first_cost).abs < BigDecimal("0.01") }
      column_validations[col] = {
        expected: consistent ? first_cost.to_f : "Inconsistent",
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Duplicate Grouped record"
      }
    end

    PERCENTAGE_COLUMNS.each do |col|
      column_validations[col] = {
        expected: "Not Calculable",
        actual: parse_big_decimal(row_value(grp_row, col)).to_f,
        status: "failed",
        message: "Duplicate Grouped record"
      }
    end

    {
      type: "duplicate_grouped",
      keys: grouping_keys,
      grouped_row_data: grp_row,
      individual_records: indiv_rows,
      columns: column_validations,
      status: "mismatch",
      message: "Duplicate grouped key detected. Expected: 1 grouped record, Found: #{count}"
    }
  end
end
