require "test_helper"
require "tempfile"
require "axlsx"

class TallyValidationServiceTest < ActiveSupport::TestCase
  HEADERS = [
    "GENERIC NAME",
    "FINANCIAL CLASS",
    "PRIMARY PAYOR NAME",
    "BENEFIT PLAN NAME",
    "HCPCS CODE",
    "NDC CODE",
    "CHARGE CLASS",
    "PACKAGE SIZE",
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
    "BLENDED CONVERSION MARGIN DIFFERENCE",
    "PRODUCT COST PER UNIT",
    "CONVERSION PRODUCT COST PER UNIT",
    "PERCENT MARGIN",
    "CONVERSION PRODUCT PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
  ].freeze

  setup do
    @temp_files = []
  end

  teardown do
    @temp_files.each do |f|
      f.close
      f.unlink
    end
  end

  test "should raise validation error if a required column is missing" do
    indiv_headers = HEADERS - [ "TOTAL INSURANCE PAYMENT" ]
    indiv_file = create_excel_file(indiv_headers, [ build_row(indiv_headers, "TOTAL INSURANCE PAYMENT" => 10) ])
    grp_file = create_excel_file(HEADERS, [ build_row(HEADERS) ])

    assert_raises(TallyValidationService::ValidationError) do
      TallyValidationService.new(indiv_file.path, grp_file.path).call
    end
  end

  test "should preserve values for headers in the first column" do
    headers = ["GENERIC NAME"] + HEADERS[1..]
    indiv_rows = [build_row(headers, "GENERIC NAME" => "TestDrug", "TOTAL UNITS" => 10)]
    grp_rows = [build_row(headers, "GENERIC NAME" => "TestDrug", "TOTAL UNITS" => 10)]

    indiv_file = create_excel_file(headers, indiv_rows)
    grp_file = create_excel_file(headers, grp_rows)

    result = TallyValidationService.new(indiv_file.path, grp_file.path).call
    row_result = result[:validated_rows].first

    assert_equal "TestDrug", row_result[:keys]["GENERIC NAME"]
    assert_equal "passed", row_result[:columns]["TOTAL UNITS"][:status]
  end

  test "should pass validation when summation columns match expected sums" do
    # Group keys matching exactly
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    # Individual file has 2 rows that sum up to 150 units
    indiv_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 50, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 100, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    # Grouped file has 1 row with 150 units
    grp_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 150, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    indiv_file = create_excel_file(HEADERS, indiv_rows)
    grp_file = create_excel_file(HEADERS, grp_rows)

    service = TallyValidationService.new(indiv_file.path, grp_file.path)
    result = service.call

    row_result = result[:validated_rows].first
    assert_equal "match", row_result[:status]
    assert_equal "passed", row_result[:columns]["TOTAL UNITS"][:status]
    assert_equal 150.0, row_result[:columns]["TOTAL UNITS"][:actual]
  end

  test "should fail validation when summation columns do not match expected sums" do
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    indiv_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 50, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    # Grouped says 60, but individual only had 50
    grp_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 60, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    indiv_file = create_excel_file(HEADERS, indiv_rows)
    grp_file = create_excel_file(HEADERS, grp_rows)

    result = TallyValidationService.new(indiv_file.path, grp_file.path).call

    row_result = result[:validated_rows].first
    assert_equal "mismatch", row_result[:status]
    assert_equal "failed", row_result[:columns]["TOTAL UNITS"][:status]
    assert_equal 10.0, row_result[:columns]["TOTAL UNITS"][:diff]
  end

  test "should validate cost columns correctly (consistent vs inconsistent)" do
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    # Case A: Consistent (both have cost 10.0)
    indiv_rows_a = [
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 10.0)),
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 10.0))
    ]
    grp_rows_a = [
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 10.0))
    ]

    indiv_file_a = create_excel_file(HEADERS, indiv_rows_a)
    grp_file_a = create_excel_file(HEADERS, grp_rows_a)

    result_a = TallyValidationService.new(indiv_file_a.path, grp_file_a.path).call
    assert_equal "passed", result_a[:validated_rows].first[:columns]["PRODUCT COST PER UNIT"][:status]

    # Case B: Inconsistent (costs differ: 10.0 and 12.0)
    indiv_rows_b = [
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 10.0)),
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 12.0))
    ]
    grp_rows_b = [
      build_row(HEADERS, keys.merge("PRODUCT COST PER UNIT" => 10.0))
    ]

    indiv_file_b = create_excel_file(HEADERS, indiv_rows_b)
    grp_file_b = create_excel_file(HEADERS, grp_rows_b)

    result_b = TallyValidationService.new(indiv_file_b.path, grp_file_b.path).call
    cost_res = result_b[:validated_rows].first[:columns]["PRODUCT COST PER UNIT"]
    assert_equal "failed", cost_res[:status]
    assert_equal "Individual group values are inconsistent", cost_res[:message]
  end

  test "should calculate and validate percentage formulas from grouped record" do
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    # expected percent margin = (25 / 100) * 100 = 25.0
    indiv_rows = [ build_row(HEADERS, keys) ]
    grp_rows = [
      build_row(HEADERS, keys.merge(
        "TOTAL MARGIN" => 25.0,
        "TOTAL PRODUCT COST" => 100.0,
        "PERCENT MARGIN" => 25.0 # matches expected
      ))
    ]

    indiv_file = create_excel_file(HEADERS, indiv_rows)
    grp_file = create_excel_file(HEADERS, grp_rows)

    result = TallyValidationService.new(indiv_file.path, grp_file.path).call
    pct_res = result[:validated_rows].first[:columns]["PERCENT MARGIN"]
    assert_equal "passed", pct_res[:status]
    assert_equal 25.0, pct_res[:actual]

    # test division by zero handling
    grp_rows_zero = [
      build_row(HEADERS, keys.merge(
        "TOTAL MARGIN" => 25.0,
        "TOTAL PRODUCT COST" => 0.0,
        "PERCENT MARGIN" => 0.0
      ))
    ]
    grp_file_zero = create_excel_file(HEADERS, grp_rows_zero)
    result_zero = TallyValidationService.new(indiv_file.path, grp_file_zero.path).call
    pct_res_zero = result_zero[:validated_rows].first[:columns]["PERCENT MARGIN"]
    assert_equal "warning", pct_res_zero[:status]
    assert_equal "Denominator is zero or missing", pct_res_zero[:message]
  end

  test "should use grouped rows as primary and ignore leftover individual combinations" do
    # Distinguish combinations by HCPCS (NDC is no longer a grouping column).
    keys_a = { "GENERIC NAME" => "Bevacizumab", "FINANCIAL CLASS" => "Commercial", "PRIMARY PAYOR NAME" => "ABC", "BENEFIT PLAN NAME" => "XYZ", "HCPCS CODE" => "J1111", "NDC CODE" => "111", "CHARGE CLASS" => "Drug", "PACKAGE SIZE" => "10" }
    keys_b = { "GENERIC NAME" => "Bevacizumab", "FINANCIAL CLASS" => "Commercial", "PRIMARY PAYOR NAME" => "ABC", "BENEFIT PLAN NAME" => "XYZ", "HCPCS CODE" => "J2222", "NDC CODE" => "222", "CHARGE CLASS" => "Drug", "PACKAGE SIZE" => "10" }
    keys_c = { "GENERIC NAME" => "Bevacizumab", "FINANCIAL CLASS" => "Commercial", "PRIMARY PAYOR NAME" => "ABC", "BENEFIT PLAN NAME" => "XYZ", "HCPCS CODE" => "J3333", "NDC CODE" => "333", "CHARGE CLASS" => "Drug", "PACKAGE SIZE" => "10" }

    # Individual has A (no grouped row) and C (matches grouped).
    # Grouped has B (no individual rows) and C (should tally).
    indiv_rows = [
      build_row(HEADERS, keys_a.merge("TOTAL UNITS" => 9, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, keys_c.merge("TOTAL UNITS" => 4, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, keys_c.merge("TOTAL UNITS" => 6, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]
    grp_rows = [
      build_row(HEADERS, keys_b.merge("TOTAL UNITS" => 1, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, keys_c.merge("TOTAL UNITS" => 10, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    result = TallyValidationService.new(
      create_excel_file(HEADERS, indiv_rows).path,
      create_excel_file(HEADERS, grp_rows).path
    ).call
    validated = result[:validated_rows]

    assert_equal 2, validated.size
    assert_nil validated.find { |r| r[:type] == "only_in_individual" }

    unexpected = validated.find { |r| r[:type] == "only_in_grouped" }
    assert_not_nil unexpected
    assert_equal "J2222", unexpected[:keys]["HCPCS CODE"]

    matched = validated.find { |r| r[:type] == "matched_group" }
    assert_not_nil matched
    assert_equal "J3333", matched[:keys]["HCPCS CODE"]
    assert_equal "passed", matched[:columns]["TOTAL UNITS"][:status]
    assert_equal 10.0, matched[:columns]["TOTAL UNITS"][:expected]
    assert_equal 10.0, matched[:columns]["TOTAL UNITS"][:actual]
  end

  test "should preserve negative signs when parsing percentages and currency" do
    service = TallyValidationService.new("unused", "unused")

    assert_equal BigDecimal("-12.1"), service.send(:parse_big_decimal, "-12.1%")
    assert_equal BigDecimal("-12.1"), service.send(:parse_big_decimal, -12.1)
    assert_equal BigDecimal("-12.1"), service.send(:parse_big_decimal, "(12.1%)")
    assert_equal BigDecimal("-12.1"), service.send(:parse_big_decimal, "($12.10)")
    assert_equal BigDecimal("-1234.56"), service.send(:parse_big_decimal, "-$1,234.56")
    assert_equal BigDecimal("12.1"), service.send(:parse_big_decimal, "12.1%")
    assert_equal BigDecimal("98.1"), service.send(:parse_big_decimal, "98.1%")
  end

  test "should pass percentage columns that match at 1 decimal rounding" do
    service = TallyValidationService.new("unused", "unused")

    # Grouped sheet stores 98.1% / 86.0% / -12.1% while the formula is more precise
    res = service.send(:compare_values, 98.082, 98.1, is_percentage: true)
    assert_equal "passed", res[:status]

    res = service.send(:compare_values, 86.024, 86.0, is_percentage: true)
    assert_equal "passed", res[:status]

    res = service.send(:compare_values, -12.058, -12.1, is_percentage: true)
    assert_equal "passed", res[:status]
  end

  test "should treat values within expected ± 5 as partial, not a 50-60 window" do
    service = TallyValidationService.new("unused", "unused")

    # expected 50.05 => partial range is 45.05 .. 55.05
    res = service.send(:compare_values, 50.05, 45.05, is_percentage: true)
    assert_equal "partial", res[:status]

    res = service.send(:compare_values, 50.05, 55.05, is_percentage: true)
    assert_equal "partial", res[:status]

    # just outside the ±5 radius
    res = service.send(:compare_values, 50.05, 45.04, is_percentage: true)
    assert_equal "failed", res[:status]

    res = service.send(:compare_values, 50.05, 55.06, is_percentage: true)
    assert_equal "failed", res[:status]

    # 50.00 to 60.00 is NOT the partial window
    res = service.send(:compare_values, 50.05, 60.00, is_percentage: true)
    assert_equal "failed", res[:status]
  end

  test "should keep the negative blended percent margin difference from the grouped sheet" do
    keys = {
      "GENERIC NAME" => "Bevacizumab-adcd IV Soln 100 MG/4ML (For Infusion)",
      "FINANCIAL CLASS" => "Medicare",
      "PRIMARY PAYOR NAME" => "MEDICARE",
      "BENEFIT PLAN NAME" => "MEDICARE PART A & B",
      "HCPCS CODE" => "Q5129",
      "NDC CODE" => "72606001101",
      "CHARGE CLASS" => "Outpatient",
      "PACKAGE SIZE" => "4"
    }

    # Mirrors the reported row: grouped BLENDED CONVERSION PERCENT MARGIN DIFFERENCE is -12.1%
    indiv_rows = [build_row(HEADERS, keys.merge(
      "TOTAL PRODUCT COST" => 9072.88,
      "TOTAL MARGIN" => 8898.84,
      "CONVERSION TOTAL PRODUCT COST" => 32661.00,
      "CONVERSION PRODUCT TOTAL MARGIN" => 28096.44,
      "BLENDED CONVERSION TOTAL PRODUCT COST" => 32661.00,
      "BLENDED CONVERSION TOTAL MARGIN" => 28096.44,
      "PERCENT MARGIN" => 98.1,
      "CONVERSION PRODUCT PERCENT MARGIN" => 86.0,
      "BLENDED CONVERSION PERCENT MARGIN" => 86.0,
      "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE" => -12.1
    ))]
    grp_rows = [build_row(HEADERS, keys.merge(
      "TOTAL PRODUCT COST" => 9072.88,
      "TOTAL MARGIN" => 8898.84,
      "CONVERSION TOTAL PRODUCT COST" => 32661.00,
      "CONVERSION PRODUCT TOTAL MARGIN" => 28096.44,
      "BLENDED CONVERSION TOTAL PRODUCT COST" => 32661.00,
      "BLENDED CONVERSION TOTAL MARGIN" => 28096.44,
      "PERCENT MARGIN" => 98.1,
      "CONVERSION PRODUCT PERCENT MARGIN" => 86.0,
      "BLENDED CONVERSION PERCENT MARGIN" => 86.0,
      "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE" => -12.1
    ))]

    indiv_file = create_excel_file(HEADERS, indiv_rows)
    grp_file = create_excel_file(HEADERS, grp_rows)
    result = TallyValidationService.new(indiv_file.path, grp_file.path).call

    diff_res = result[:validated_rows].first[:columns]["BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"]
    assert_operator diff_res[:actual], :<, 0
    assert_in_delta(-12.1, diff_res[:actual], 0.001)
    assert_equal "passed", diff_res[:status]

    pct_res = result[:validated_rows].first[:columns]["PERCENT MARGIN"]
    assert_equal "passed", pct_res[:status]
  end

  test "should match grouped and individual rows when headers use underscores" do
    underscore_headers = HEADERS.map { |h| h.tr(" ", "_") }
    keys = {
      "GENERIC NAME" => "Bevacizumab-awwb IV Soln 100 MG/4ML (For Infusion)",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "UNITED HEALTHCARE",
      "BENEFIT PLAN NAME" => "UNITED HEALTHCARE CHOICE PLUS",
      "HCPCS CODE" => "Q5107",
      "NDC CODE" => "55513020701",
      "CHARGE CLASS" => "Outpatient",
      "PACKAGE SIZE" => 16
    }

    indiv_rows = [build_row(underscore_headers, keys.merge("TOTAL UNITS" => 7, "PRODUCT COST PER UNIT" => 635.57, "CONVERSION PRODUCT COST PER UNIT" => 635.57))]
    grp_rows = [build_row(underscore_headers, keys.merge("TOTAL UNITS" => 7, "PRODUCT COST PER UNIT" => 635.57, "CONVERSION PRODUCT COST PER UNIT" => 635.57))]

    result = TallyValidationService.new(
      create_excel_file(underscore_headers, indiv_rows).path,
      create_excel_file(underscore_headers, grp_rows).path
    ).call

    row_result = result[:validated_rows].first
    assert_equal "matched_group", row_result[:type]
    assert_equal "Bevacizumab-awwb IV Soln 100 MG/4ML (For Infusion)", row_result[:keys]["GENERIC NAME"]
    assert_equal "passed", row_result[:columns]["TOTAL UNITS"][:status]
  end

  test "should match package size 16 with 16.0 and dashed NDC codes" do
    keys = {
      "GENERIC NAME" => "Bevacizumab-awwb IV Soln 100 MG/4ML (For Infusion)",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "UNITED HEALTHCARE",
      "BENEFIT PLAN NAME" => "UNITED HEALTHCARE CHOICE PLUS",
      "HCPCS CODE" => "Q5107",
      "CHARGE CLASS" => "Outpatient"
    }

    indiv_rows = [build_row(HEADERS, keys.merge(
      "NDC CODE" => "55513-0207-01",
      "PACKAGE SIZE" => 16.0,
      "TOTAL UNITS" => 7,
      "PRODUCT COST PER UNIT" => 10.0,
      "CONVERSION PRODUCT COST PER UNIT" => 10.0
    ))]
    grp_rows = [build_row(HEADERS, keys.merge(
      "NDC CODE" => "55513020701",
      "PACKAGE SIZE" => 16,
      "TOTAL UNITS" => 7,
      "PRODUCT COST PER UNIT" => 10.0,
      "CONVERSION PRODUCT COST PER UNIT" => 10.0
    ))]

    result = TallyValidationService.new(
      create_excel_file(HEADERS, indiv_rows).path,
      create_excel_file(HEADERS, grp_rows).path
    ).call

    assert_equal 1, result[:validated_rows].size
    row_result = result[:validated_rows].first
    assert_equal "matched_group", row_result[:type]
    assert_equal "match", row_result[:status]
    assert_equal "16", row_result[:keys]["PACKAGE SIZE"]
    assert_nil row_result[:keys]["NDC CODE"]
  end

  test "should include individual rows that differ only on NDC code" do
    shared = {
      "GENERIC NAME" => "Bevacizumab-awwb IV Soln 100 MG/4ML (For Infusion)",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "UNITED HEALTHCARE",
      "BENEFIT PLAN NAME" => "UNITED HEALTHCARE CHOICE PLUS",
      "HCPCS CODE" => "Q5107",
      "CHARGE CLASS" => "Outpatient",
      "PACKAGE SIZE" => 16,
      "PRODUCT COST PER UNIT" => 635.57,
      "CONVERSION PRODUCT COST PER UNIT" => 635.57,
      "TOTAL UNITS" => 1
    }

    # Different NDCs still group together now that NDC is not a grouping column
    indiv_rows = Array.new(6) { build_row(HEADERS, shared.merge("NDC CODE" => "55513020721")) }
    indiv_rows.unshift(build_row(HEADERS, shared.merge("NDC CODE" => "55513020701")))

    grp_rows = [build_row(HEADERS, shared.merge("NDC CODE" => "55513020721", "TOTAL UNITS" => 7))]

    result = TallyValidationService.new(
      create_excel_file(HEADERS, indiv_rows).path,
      create_excel_file(HEADERS, grp_rows).path
    ).call

    row_result = result[:validated_rows].first
    assert_equal "matched_group", row_result[:type]
    assert_equal 7, row_result[:individual_records].size
    assert_equal "passed", row_result[:columns]["TOTAL UNITS"][:status]
    assert_equal 7.0, row_result[:columns]["TOTAL UNITS"][:expected]
    assert_equal 7.0, row_result[:columns]["TOTAL UNITS"][:actual]
  end

  test "should include the last data row unless it is a totals row" do
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    indiv_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 50, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 100, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]
    grp_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 150, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0))
    ]

    result = TallyValidationService.new(
      create_excel_file(HEADERS, indiv_rows).path,
      create_excel_file(HEADERS, grp_rows).path
    ).call

    row_result = result[:validated_rows].first
    assert_equal "match", row_result[:status]
    assert_equal "passed", row_result[:columns]["TOTAL UNITS"][:status]
    assert_equal 150.0, row_result[:columns]["TOTAL UNITS"][:actual]
    assert_equal 150.0, row_result[:columns]["TOTAL UNITS"][:expected]
  end

  test "should skip a trailing totals row" do
    keys = {
      "GENERIC NAME" => "Bevacizumab",
      "FINANCIAL CLASS" => "Commercial",
      "PRIMARY PAYOR NAME" => "ABC",
      "BENEFIT PLAN NAME" => "XYZ",
      "HCPCS CODE" => "J9035",
      "NDC CODE" => "12345678901",
      "CHARGE CLASS" => "Drug",
      "PACKAGE SIZE" => "10"
    }

    indiv_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 50, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, "GENERIC NAME" => "Total", "TOTAL UNITS" => 999)
    ]
    grp_rows = [
      build_row(HEADERS, keys.merge("TOTAL UNITS" => 50, "PRODUCT COST PER UNIT" => 10.0, "CONVERSION PRODUCT COST PER UNIT" => 8.0)),
      build_row(HEADERS, "GENERIC NAME" => "Total", "TOTAL UNITS" => 999)
    ]

    result = TallyValidationService.new(
      create_excel_file(HEADERS, indiv_rows).path,
      create_excel_file(HEADERS, grp_rows).path
    ).call

    assert_equal 1, result[:validated_rows].size
    assert_equal "matched_group", result[:validated_rows].first[:type]
    assert_equal 50.0, result[:validated_rows].first[:columns]["TOTAL UNITS"][:expected]
  end

  private

  def create_excel_file(headers, rows)
    temp = Tempfile.new([ "tally_test", ".xlsx" ])
    p = Axlsx::Package.new
    p.workbook.add_worksheet(name: "Sheet1") do |sheet|
      sheet.add_row(headers)
      rows.each { |r| sheet.add_row(r) }
    end
    p.serialize(temp.path)
    @temp_files << temp
    temp
  end

  def build_row(headers, values_hash = {})
    headers.map do |col|
      canonical = col.to_s.tr("_", " ")
      if values_hash.key?(col)
        values_hash[col]
      elsif values_hash.key?(canonical)
        values_hash[canonical]
      else
        default_value_for_col(canonical)
      end
    end
  end

  def default_value_for_col(col)
    case col
    when "GENERIC NAME" then "Bevacizumab"
    when "FINANCIAL CLASS" then "Commercial"
    when "PRIMARY PAYOR NAME" then "ABC"
    when "BENEFIT PLAN NAME" then "XYZ"
    when "HCPCS CODE" then "J9035"
    when "NDC CODE" then "12345678901"
    when "CHARGE CLASS" then "Drug"
    when "PACKAGE SIZE" then "10"
    when "PERCENT MARGIN", "CONVERSION PRODUCT PERCENT MARGIN", "BLENDED CONVERSION PERCENT MARGIN", "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
      0.0
    else
      if [
        "TOTAL UNITS", "CMS TOTAL UNITS", "TOTAL PRODUCT COST", "TOTAL INSURANCE PAYMENT",
        "ACTUAL REIMBURSEMENT", "TOTAL MARGIN", "CONVERSION TOTAL PRODUCT COST",
        "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT", "CONVERSION PRODUCT TOTAL MARGIN",
        "BLENDED CONVERSION TOTAL PRODUCT COST", "BLENDED CONVERSION TOTAL MARGIN",
        "BLENDED CONVERSION COST DIFFERENCE", "BLENDED CONVERSION MARGIN DIFFERENCE",
        "PRODUCT COST PER UNIT", "CONVERSION PRODUCT COST PER UNIT"
      ].include?(col)
        0.0
      else
        ""
      end
    end
  end
end
