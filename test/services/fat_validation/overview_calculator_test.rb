# frozen_string_literal: true

require "test_helper"

class FatValidation::OverviewCalculatorTest < ActiveSupport::TestCase
  test "sums blended conversion margin difference with to_i for the drug name" do
    create_conversion(create_report("Bevacizumab"), 10.9)
    create_conversion(create_report("Bevacizumab"), 0.2)
    create_conversion(create_report("Bevacizumab"), nil)

    other = create_report("Rituximab")
    create_conversion(other, 50)

    ignored = create_report("Bevacizumab", category: "grouped")
    create_conversion(ignored, 999)

    wrong_type = create_report("Bevacizumab")
    create_conversion(wrong_type, 80, conversion_type: "percentage")

    results = FatValidation::Calculators::OverviewCalculator.new(
      team_id: "147",
      accounting_period_id: 8
    ).call([ "Bevacizumab", "Rituximab", "Missing Drug" ])

    by_name = results.index_by { |row| row[:generic_group] }
    assert_equal 11, by_name["Bevacizumab"][:expected_value]
    assert_equal 3, by_name["Bevacizumab"][:details]["invoice_conversion_count"]
    assert_equal 50, by_name["Rituximab"][:expected_value]
    assert_equal 0, by_name["Missing Drug"][:expected_value]
    assert_equal 0, by_name["Missing Drug"][:details]["utilization_report_count"]
  end

  test "database processor refuses reports other than overview" do
    run = FatValidationRun.new(report_type: "margin", team_id: "147", accounting_period_id: 8)

    error = assert_raises(FatValidation::Error) do
      FatValidation::DataSources::DatabaseProcessor.new(run: run, generic_groups: [ "Bevacizumab" ]).call
    end
    assert_match "margin", error.message
  end

  private

  def create_report(group, category: nil)
    UtilizationAnalytics::Tables.utilization_reports.create!(
      team_id: "147",
      accounting_period_id: 8,
      category: category,
      generic_name_group: group
    )
  end

  def create_conversion(report, margin, conversion_type: "highest_margin")
    UtilizationAnalytics::Tables.relation("invoice_conversions").create!(
      utilization_report_id: report.id,
      team_id: "147",
      conversion_type: conversion_type,
      status: "individual",
      blended_conversion_margin_difference: margin
    )
  end
end
