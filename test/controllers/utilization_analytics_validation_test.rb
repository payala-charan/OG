# frozen_string_literal: true

require "test_helper"
require_relative "../support/utilization_analytics_validation_data"

class UtilizationAnalyticsValidationTest < ActionDispatch::IntegrationTest
  include UtilizationAnalyticsValidationData

  setup do
    @user = User.create!(
      email: "analytics-validation-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  teardown { clear_validation_data }

  test "validation endpoint compares the posted endpoint payload with the database" do
    seed_period!(accounting_period_id: 6)
    seed_period!(accounting_period_id: 7, data_month: "July 2026")
    seed_standard_prices!(6)
    seed_standard_prices!(7)
    log_in

    post validate_utilization_analytics_path, params: {
      team_id: "198",
      period_kind: "quarter",
      group: validation_group,
      quarter_name1: "Quarter 1 2026",
      quarter_name2: "Quarter 2 2026",
      charge_class: "Outpatient",
      analytics: {
        comparison: {
          total_units: {
            visible: true,
            rows: [ { brand: validation_brand, baseline: 140, comparator: 140 } ]
          }
        }
      }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "passed", body["status"]
    assert_equal "Validation Passed", body["message"]
    assert_equal "Total Units", body["metrics"].first["metric"]
    assert_equal "passed", body["metrics"].first["status"]
  end

  private

  def log_in
    post login_path, params: { email: @user.email, password: "password123" }
  end
end
