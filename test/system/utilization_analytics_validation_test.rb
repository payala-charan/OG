# frozen_string_literal: true

require "application_system_test_case"
require_relative "../support/fake_utilization_analytics_server"

class UtilizationAnalyticsValidationTest < ApplicationSystemTestCase
  setup do
    @previous_wait = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 15
    @user = User.create!(
      email: "analytics-validation-ui-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
    @previous_base_url = ENV["BASE_URL"]
    @api = FakeUtilizationAnalyticsServer.new
    ENV["BASE_URL"] = @api.base_url
  end

  teardown do
    Capybara.default_max_wait_time = @previous_wait if @previous_wait
    ENV["BASE_URL"] = @previous_base_url
    @api&.stop
  end

  test "verification button sends the current filters and renders passed and failed results" do
    visit login_path
    fill_in "Email Address", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Login Now"
    click_link "Utilization Analytics"

    assert_no_selector "#ua-validate-btn"
    within "#quarterly-form" do
      select "BEVACIZUMAB", from: "Select Generic Group"
      select "Quarter 4 2025", from: "Select Baseline"
      select "Quarter 1 2026", from: "Select Comparator"
    end
    click_button "Compare"

    assert_text "API GRAND"
    assert_button "Verification / Validation"
    stub_validation(status: "passed", message: "Validation Passed", metric_status: "passed")
    click_button "Verification / Validation"

    assert_text "Validating…"
    assert_text "Validation Passed"
    assert_selector ".ua-validation-banner--passed"
    assert_selector ".ua-validation-status--passed", text: "✓ Passed"
    assert_text "API GRAND"
    body = page.evaluate_script("window.__lastValidationBody")
    assert_includes body, "BEVACIZUMAB"
    assert_includes body, "Quarter 4 2025"
    assert_includes body, "Quarter 1 2026"
    assert_includes body, "\"team_id\":\"209\""

    stub_validation(status: "failed", message: "Validation Failed", metric_status: "failed")
    click_button "Verification / Validation"
    assert_text "Validation Failed"
    assert_selector ".ua-validation-banner--failed"
    assert_selector ".ua-validation-row--failed .ua-validation-status--failed", text: "✗ Failed"
    assert_text "API GRAND"
  end

  private

  def stub_validation(status:, message:, metric_status:)
    page.execute_script(<<~JS, status, message, metric_status)
      const status = arguments[0];
      const message = arguments[1];
      const metricStatus = arguments[2];
      window.fetch = (url, options) => new Promise((resolve) => {
        window.__lastValidationBody = options.body;
        setTimeout(() => {
          resolve({
            ok: true,
            json: () => Promise.resolve({
              status: status,
              message: message,
              metrics: [ {
                metric: "Total Units",
                brand: "AVASTIN",
                period: "baseline",
                period_label: "Quarter 4 2025",
                displayed_value: 10,
                db_value: metricStatus === "passed" ? 10 : 12,
                status: metricStatus
              } ]
            })
          });
        }, 400);
      });
    JS
  end
end
