# frozen_string_literal: true

require "test_helper"

class FatValidation::ValidationComparatorTest < ActiveSupport::TestCase
  setup do
    @comparator = FatValidation::ValidationComparator.new
  end

  test "matches by drug name and ignores row order" do
    actual = [
      row("Rituximab", 50, "$50"),
      row("Bevacizumab", 11, "$11")
    ]
    expected = [
      expected("Bevacizumab", 11),
      expected("Rituximab", 50)
    ]

    results = @comparator.compare(actual_rows: actual, expected_rows: expected)

    assert_equal [ "PASS", "PASS" ], results.map { |item| item[:status] }
    bevacizumab = results.find { |item| item[:generic_group] == "Bevacizumab" }
    assert_equal 0, bevacizumab[:difference]
    assert_equal "$11", bevacizumab[:details]["raw_actual"]
  end

  test "fails mismatches, blank opportunity, and duplicate drug names" do
    actual = [
      row("Bevacizumab", 10, "$10"),
      row("Rituximab", nil, "—"),
      row("Infliximab", 5, "$5"),
      row("Infliximab", 5, "$5")
    ]
    expected = [
      expected("Bevacizumab", 11),
      expected("Rituximab", 0)
    ]

    results = @comparator.compare(actual_rows: actual, expected_rows: expected)
    by_name = results.group_by { |item| item[:generic_group] }

    assert_equal "FAIL", by_name["Bevacizumab"].first[:status]
    assert_equal(-1, by_name["Bevacizumab"].first[:difference])
    assert_equal "FAIL", by_name["Rituximab"].first[:status]
    assert_equal [ "DUPLICATE", "DUPLICATE" ], by_name["Infliximab"].map { |item| item[:status] }
  end

  test "parses overview dollar text as whole dollars" do
    assert_equal 741_544, FatValidation::Money.parse_dollars("$741,544")
    assert_equal 0, FatValidation::Money.parse_dollars("$0")
    assert_nil FatValidation::Money.parse_dollars("—")
    assert_equal(-12, FatValidation::Money.parse_dollars("($12)"))
  end

  private

  def row(name, actual, raw)
    FatValidation::Selenium::FrontendExtractor::DrugRow.new(
      generic_group: name,
      actual_value: actual,
      raw_actual: raw
    )
  end

  def expected(name, value)
    { generic_group: name, expected_value: value, details: { "utilization_report_count" => 1 } }
  end
end
