# frozen_string_literal: true

require "test_helper"

class FatValidation::ResultBuilderTest < ActiveSupport::TestCase
  test "stores every comparison and the pass fail counts" do
    run = FatValidationRun.create!(
      team_id: "147",
      environment: "staging",
      report_type: "overview",
      data_source: "database",
      status: :running
    )

    FatValidation::ResultBuilder.new(run).save!([
      { generic_group: "Bevacizumab", column_name: "opportunity", expected_value: 11, actual_value: 11, difference: 0, status: "PASS", details: {} },
      { generic_group: "Rituximab", column_name: "opportunity", expected_value: 50, actual_value: 40, difference: -10, status: "FAIL", details: { "reason" => "Opportunity does not match." } }
    ])

    run.reload
    assert run.completed?
    assert_equal 2, run.total_records
    assert_equal 1, run.passed_records
    assert_equal 1, run.failed_records
    assert_equal %w[Bevacizumab Rituximab], run.results.order(:generic_group).pluck(:generic_group)
  end
end
