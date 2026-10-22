# frozen_string_literal: true

require "test_helper"
require_relative "../../support/utilization_analytics_validation_data"

class UtilizationAnalytics::ValidationServiceTest < ActiveSupport::TestCase
  include UtilizationAnalyticsValidationData

  teardown { clear_validation_data }

  test "an exact quarterly match passes and a meaningful difference fails" do
    seed_period!(accounting_period_id: 6)
    seed_period!(accounting_period_id: 7, data_month: "July 2026")
    seed_standard_prices!(6)
    seed_standard_prices!(7)

    passed = validate(analytics_for(units: 140, cost_per_unit: 2.5, product_cost: 350, margin: 230, per_unit: 230.0 / 140, percent: (230.0 / 350) * 100))
    assert_equal "passed", passed["status"]
    assert_equal "Validation Passed", passed["message"]
    assert passed["metrics"].all? { |row| row["status"] == "passed" }
    units = passed["metrics"].find { |row| row["metric"] == "Total Units" && row["period"] == "baseline" }
    assert_in_delta 140, units["db_value"]
    assert_in_delta 0, units["difference"]

    failed = validate(analytics_for(units: 140, cost_per_unit: 11.13, product_cost: 350, margin: 230, per_unit: 230.0 / 140, percent: (230.0 / 350) * 100))
    assert_equal "failed", failed["status"]
    assert_equal "Validation Failed", failed["message"]
    cost = failed["metrics"].find { |row| row["metric"] == "Product Cost Per Unit" && row["period"] == "baseline" }
    assert_equal "failed", cost["status"]
    assert_in_delta 11.13, cost["displayed_value"]
    assert_in_delta 2.5, cost["db_value"]
    assert_in_delta 8.63, cost["difference"]
  end

  test "values that round to the same two decimals pass" do
    seed_period!(accounting_period_id: 6)
    seed_period!(accounting_period_id: 7, data_month: "July 2026")
    seed_standard_prices!(6)
    seed_standard_prices!(7)

    result = validate(analytics_for(
      units: 140.004,
      cost_per_unit: 2.504,
      product_cost: 350.004,
      margin: 229.996,
      per_unit: 1.642,
      percent: 65.714
    ))

    assert_equal "passed", result["status"], result["metrics"].map { |row| [ row["metric"], row["period"], row["status"], row["message"] ] }.inspect
  end

  test "monthly validation filters by data_month and still prices from period 7" do
    seed_period!(accounting_period_id: 4, data_month: "April 2026")
    seed_period!(accounting_period_id: 4, data_month: "May 2026")
    add_price!(accounting_period_id: 4, ndc_code: "AAA", billing_unit_per_package_size: 100)
    seed_standard_prices!(7)

    result = validate(
      analytics_for(units: 140, cost_per_unit: 2.5, product_cost: 350, margin: 230, per_unit: 230.0 / 140, percent: (230.0 / 350) * 100),
      period_kind: "month",
      data_month1: "April 2026",
      data_month2: "May 2026"
    )

    assert_equal "passed", result["status"], result["metrics"].inspect
    assert_equal 7, UtilizationAnalytics::Period.quarter(role: "baseline", label: "Quarter 1 2026", accounting_period_id: 6).price_accounting_period_id
  end

  test "a missing endpoint value and a missing package size are validation errors" do
    seed_period!(accounting_period_id: 6)
    seed_period!(accounting_period_id: 7, data_month: "July 2026")

    missing = validate(analytics_for(units: nil, cost_per_unit: 2.5, product_cost: 350, margin: 230, per_unit: 1, percent: 1))
    units = missing["metrics"].find { |row| row["metric"] == "Total Units" && row["period"] == "baseline" }
    assert_equal "error", units["status"]
    assert_match "Endpoint value", units["message"]

    priced = validate(analytics_for(units: 140, cost_per_unit: 2.5, product_cost: 350, margin: 230, per_unit: 1, percent: 1))
    cost = priced["metrics"].find { |row| row["metric"] == "Product Cost Per Unit" }
    assert_equal "error", cost["status"]
    assert_match "NDC AAA", cost["message"]
    assert_equal "error", priced["status"]
  end

  test "calculation proof line counts compare to database record counts" do
    seed_period!(accounting_period_id: 6)
    seed_period!(accounting_period_id: 7, data_month: "July 2026")
    seed_standard_prices!(6)
    seed_standard_prices!(7)
    payload = analytics_for(units: 140, cost_per_unit: 2.5, product_cost: 350, margin: 230, per_unit: 230.0 / 140, percent: (230.0 / 350) * 100)
    payload["comparison"]["total_units"]["proof"] = {
      "show_inpatient_row_count" => true,
      "rows" => {
        validation_brand => { "q1_inpatient_row_count" => 1, "q2_inpatient_row_count" => 1 }
      }
    }
    payload["comparison"]["product_cost_per_unit"]["proof"] = {
      "rows" => {
        validation_brand => {
          "q1" => { "purchase_lines_included" => 2 },
          "q2" => { "purchase_lines_included" => 2 }
        }
      }
    }

    result = validate(payload)
    assert_equal "passed", result["status"], result["metrics"].inspect
    inpatient = result["metrics"].find { |row| row["metric"] == "Inpatient lines" && row["period"] == "baseline" }
    lines = result["metrics"].find { |row| row["metric"] == "Purchase lines" && row["period"] == "comparator" }
    assert_equal "passed", inpatient["status"]
    assert_equal 1, inpatient["db_value"]
    assert_equal "passed", lines["status"]
    assert_equal 2, lines["db_value"]

    payload["comparison"]["total_units"]["proof"]["rows"][validation_brand]["q1_inpatient_row_count"] = 9
    failed = validate(payload)
    assert_equal "failed", failed["status"]
    assert_equal "failed", failed["metrics"].find { |row| row["metric"] == "Inpatient lines" && row["period"] == "baseline" }["status"]
  end

  test "date range and a missing payload do not raise" do
    range = UtilizationAnalytics::ValidationService.new(
      team_id: "198",
      params: { period_kind: "date_range", group: validation_group },
      analytics_data: {}
    ).call
    assert_equal "error", range["status"]
    assert_match "monthly and quarterly", range["message"]

    missing = UtilizationAnalytics::ValidationService.new(
      team_id: "198",
      params: { period_kind: "quarter", quarter_name1: "Quarter 1 2026", quarter_name2: "Quarter 2 2026" },
      analytics_data: {}
    ).call
    assert_equal "error", missing["status"]
    assert_match "Endpoint data is missing", missing["message"]
  end

  private

  def validate(analytics, **overrides)
    UtilizationAnalytics::ValidationService.new(
      team_id: "198",
      params: {
        period_kind: "quarter",
        group: validation_group,
        quarter_name1: "Quarter 1 2026",
        quarter_name2: "Quarter 2 2026",
        charge_class: "Outpatient"
      }.merge(overrides),
      analytics_data: analytics
    ).call
  end

  def analytics_for(units:, cost_per_unit:, product_cost:, margin:, per_unit:, percent:)
    {
      "comparison" => {
        "total_units" => section("Total Units", units, units),
        "product_cost_per_unit" => section("Product Cost Per Unit", cost_per_unit, cost_per_unit),
        "product_cost" => section("Total Product Cost", product_cost, product_cost),
        "total_margin" => section("Total Margin", margin, margin),
        "margin_per_unit" => section("Margin Per Unit", per_unit, per_unit),
        "margin_percent_of_cost" => section("Margin % of Cost", percent, percent)
      }
    }
  end

  def section(title, baseline, comparator)
    row = { "brand" => validation_brand, "comparator" => comparator }
    row["baseline"] = baseline unless baseline.nil?
    {
      "title" => title,
      "visible" => true,
      "rows" => [ row, { "brand" => "Total", "baseline" => 1, "comparator" => 1 } ]
    }
  end
end
