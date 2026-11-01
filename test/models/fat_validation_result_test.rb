# frozen_string_literal: true

require "test_helper"

class FatValidationResultTest < ActiveSupport::TestCase
  setup do
    @run = FatValidationRun.create!(
      team_id: "198",
      environment: "local",
      report_type: "overview",
      data_source: "database",
      status: :pending
    )
  end

  test "accepts pass and fail statuses and stores details" do
    result = @run.results.create!(
      generic_group: "Bevacizumab",
      column_name: "opportunity",
      expected_value: 100,
      actual_value: 90,
      difference: -10,
      status: "FAIL",
      details: { "reason" => "Opportunity does not match." }
    )

    assert result.persisted?
    assert_not result.pass?
    assert_equal "Opportunity does not match.", result.reload.details["reason"]
  end

  test "rejects an unknown status" do
    result = @run.results.new(column_name: "opportunity", status: "MAYBE")

    assert_not result.valid?
  end
end
