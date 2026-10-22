# frozen_string_literal: true

require "test_helper"
require_relative "../../support/utilization_analytics_validation_data"

class UtilizationAnalytics::CalculatorTest < ActiveSupport::TestCase
  include UtilizationAnalyticsValidationData

  teardown { clear_validation_data }

  test "quarter labels resolve to accounting periods without using a fixed pair in the math" do
    assert_equal 6, UtilizationAnalytics::Periods.accounting_period_id("Quarter 1 2026")
    assert_equal 7, UtilizationAnalytics::Periods.accounting_period_id("Quarter 2 2026")
    assert_equal 5, UtilizationAnalytics::Periods.accounting_period_id("Q4 2025")
    assert_equal 7, UtilizationAnalytics::Periods::PRICE_PERIOD_ID
    assert_equal 7, quarter("baseline", "Quarter 1 2026", 6).price_accounting_period_id
  end

  test "quarterly metrics use the selected accounting period and price package sizes from period 7" do
    seed_period!(accounting_period_id: 6)
    seed_standard_prices!(7)
    add_price!(accounting_period_id: 6, ndc_code: "AAA", billing_unit_per_package_size: 100)
    other = add_report!(team_id: "209", accounting_period_id: 6, cms_total_units: 80, actual_reimbursement: 80)
    add_ndc!(other, ndc_code: "OTHER-TEAM")

    result = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))

    assert_in_delta 140, result.units
    assert_in_delta 580, result.reimbursement
    assert_in_delta 2.5, result.cost_per_unit
    assert_in_delta 350, result.product_cost
    assert_in_delta 230, result.total_margin
    assert_in_delta 230.0 / 140, result.margin_per_unit
    assert_in_delta (230.0 / 350) * 100, result.margin_percent
    assert_equal 1, result.inpatient_count
    assert_equal 2, result.purchase_line_count
    assert_nil result.cost_error
  end

  test "monthly utilization and purchases use data_month while prices stay on period 7" do
    seed_period!(accounting_period_id: 6, data_month: "April 2026")
    add_report!(
      accounting_period_id: 6,
      data_month: "May 2026",
      cms_total_units: 500,
      actual_reimbursement: 500
    ).tap { |report| add_ndc!(report, ndc_code: "MAY") }
    add_purchase!(
      accounting_period_id: 6,
      data_month: "May 2026",
      invoice_price: 99,
      total_quantity_ordered: 9,
      ndc_product_id: "AAA"
    )
    add_price!(accounting_period_id: 6, ndc_code: "AAA", billing_unit_per_package_size: 100)
    add_price!(accounting_period_id: 7, ndc_code: "AAA", billing_unit_per_package_size: 4)
    add_price!(accounting_period_id: 7, ndc_code: "NOPE", alternate_ndc_code: "BBB", billing_unit_per_package_size: 2)

    result = calculator_for.measure(validation_brand, month("baseline", "April 2026"))

    assert_in_delta 140, result.units
    assert_in_delta 580, result.reimbursement
    assert_in_delta 2.5, result.cost_per_unit
    assert_equal 2, result.purchase_line_count
  end

  test "ndc lookup prefers ndc_code, then alternate, and reports missing or conflicting sizes" do
    seed_period!(accounting_period_id: 6)
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 4, accounting_period_id: 7)
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 4, accounting_period_id: 7)
    add_price!(ndc_code: "DECOY", alternate_ndc_code: "AAA", billing_unit_per_package_size: 99, accounting_period_id: 7)
    add_price!(ndc_code: "SKIP", alternate_ndc_code: "BBB", billing_unit_per_package_size: 2, accounting_period_id: 7)

    matched = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))
    assert_in_delta 2.5, matched.cost_per_unit

    NewBiosimilarPrice.where(id: validation_ids[:prices]).delete_all
    validation_ids[:prices].clear
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: nil, accounting_period_id: 7)
    add_price!(ndc_code: "BBB", billing_unit_per_package_size: nil, accounting_period_id: 7)
    missing = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))
    assert_match(/NDC (AAA|BBB)/, missing.cost_error)

    add_price!(ndc_code: "BBB", billing_unit_per_package_size: 2, accounting_period_id: 7)
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 4, accounting_period_id: 7)
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 9, accounting_period_id: 7)
    conflict = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))
    assert_match "multiple billing unit/package sizes", conflict.cost_error
    assert_match "NDC AAA", conflict.cost_error
  end

  test "an ndc shorter than 11 characters matches the zero-padded biosimilar code" do
    add_purchase!(invoice_price: 10, total_quantity_ordered: 2, ndc_product_id: "69034201")
    add_price!(ndc_code: "69034201", billing_unit_per_package_size: 99, accounting_period_id: 7)
    add_price!(ndc_code: "00069034201", billing_unit_per_package_size: 4, accounting_period_id: 7)

    result = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))

    assert_nil result.cost_error
    assert_in_delta 2.5, result.cost_per_unit

    clear_validation_data
    add_purchase!(invoice_price: 10, total_quantity_ordered: 2, ndc_product_id: "69034201")
    add_price!(ndc_code: "OTHER", alternate_ndc_code: "00069034201", billing_unit_per_package_size: 4, accounting_period_id: 7)
    alternate = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))
    assert_nil alternate.cost_error
    assert_in_delta 2.5, alternate.cost_per_unit
  end

  test "a zero billing total is a validation error" do
    add_purchase!(invoice_price: 10, total_quantity_ordered: 5, ndc_product_id: "AAA")
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 0, accounting_period_id: 7)

    result = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))

    assert_match "total billing units are zero", result.cost_error
    assert_nil result.cost_per_unit
  end

  test "margin per unit and margin percent stay safe when a denominator is zero" do
    add_report!(cms_total_units: 0, actual_reimbursement: 25).tap { |report| add_ndc!(report) }
    add_purchase!(invoice_price: 10, total_quantity_ordered: 2, ndc_product_id: "AAA")
    add_price!(ndc_code: "AAA", billing_unit_per_package_size: 4, accounting_period_id: 7)

    result = calculator_for.measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))

    assert_in_delta 2.5, result.cost_per_unit
    assert_in_delta 0, result.product_cost
    assert_match "CMS total units are zero", result.margin_per_unit_error
    assert_match "total product cost is zero", result.margin_percent_error
  end

  test "hospital and payor filters limit utilization rows" do
    main = add_report!(cms_total_units: 10, actual_reimbursement: 30, hospital_name: "Main")
    add_ndc!(main, ndc_code: "MAIN")
    add_payor!(main, name: "Aetna")
    east = add_report!(cms_total_units: 70, actual_reimbursement: 90, hospital_name: "East")
    add_ndc!(east, ndc_code: "EAST")
    add_payor!(east, name: "Cigna")

    by_hospital = calculator_for(hospital_names: [ "Main" ]).measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))
    by_payor = calculator_for(payor_names: [ "Aetna" ]).measure(validation_brand, quarter("baseline", "Quarter 1 2026", 6))

    assert_in_delta 10, by_hospital.units
    assert_in_delta 30, by_hospital.reimbursement
    assert_in_delta 10, by_payor.units
  end

  private

  def quarter(role, label, id)
    UtilizationAnalytics::Period.quarter(role: role, label: label, accounting_period_id: id)
  end

  def month(role, name)
    UtilizationAnalytics::Period.month(role: role, label: name, data_month: name)
  end
end
