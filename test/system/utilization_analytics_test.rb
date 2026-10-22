# frozen_string_literal: true

require "application_system_test_case"
require_relative "../support/fake_utilization_analytics_server"

class UtilizationAnalyticsTest < ApplicationSystemTestCase
  setup do
    @previous_wait = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 15
    @user = User.create!(
      email: "analytics-ui-#{SecureRandom.hex(6)}@example.com",
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

  test "loads controls from the api and plots returned comparison and trend charts" do
    visit login_path
    fill_in "Email Address", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Login Now"
    assert_selector "a", text: "Open Analytics", visible: :all
    click_link "Utilization Analytics"

    assert_text "Select a group and two periods to view the comparison."
    assert_equal [ "209" ], @api.requests.first["team_id"]
    assert_not @api.requests.first.key?("user_id")
    assert_not @api.requests.first.key?("group")
    assert_selector "select#teamSelect option[selected]", text: "209"

    select "198", from: "Team"
    assert_equal [ "198" ], @api.requests.last["team_id"]
    assert_not @api.requests.last.key?("user_id")
    assert_not @api.requests.last.key?("group")

    page.driver.browser.manage.window.resize_to(390, 844)
    assert_selector "select#group"
    assert_selector "#quarter-form"
    page.driver.browser.manage.window.resize_to(1400, 900)

    within "#quarterly-form" do
      select "Filgrastim", from: "Select Generic Group"
      select "Quarter 4 2025", from: "Select Baseline"
      select "Quarter 1 2026", from: "Select Comparator"
    end
    click_button "Compare"

    assert_text "API GRAND"
    assert_text "Calculation proof — CMS Total Units"
    assert_text "OP+EM (in table)"
    assert_text "AVASTIN"
    assert_text "19108.6"
    assert_selector "#ua-section-total_units"
    assert_chart_data("#ua-chart-total_units canvas", "Total", [ 10.25, 30 ])
    assert_chart_data("#ua-chart-drug_spend canvas", "Expense Difference", [ 150.5 ])

    find("#classFilterBtn").click
    within "#classDropdown" do
      check "Inpatient"
      click_button "Apply"
    end
    assert_text "Total Units"
    assert_text "Drug Spend"
    assert_no_selector "#ua-section-total_margin"
    assert_no_selector "#ua-chart-margin_improvement"

    within "#trending-form" do
      select "Filgrastim", from: "Select Generic Group"
    end
    page.execute_script(<<~JS)
      const start = document.querySelector("#startDate");
      const end = document.querySelector("#endDate");
      start.value = "2025-10-01";
      end.value = "2026-03-31";
      end.dispatchEvent(new Event("input", { bubbles: true }));
      end.dispatchEvent(new Event("change", { bubbles: true }));
    JS
    click_button "Trend"

    assert_text "quarterly"
    assert_selector "#ua-trending h3", text: "Units"
    assert_selector "#ua-trending h3", text: "Product Cost Per Unit"
    assert_no_selector "#ua-trending h3", text: "Total Margin"
    assert_no_selector "#export-area table.ua-table"
    date_request = @api.requests.reverse.find { |params| params["start_date"]&.first.present? }
    assert_equal "2025-10-01", date_request["start_date"].first
    assert_equal "2026-03-31", date_request["end_date"].first
    assert_not date_request.key?("quarter_name1")
    assert_equal [ "198" ], date_request["team_id"]
    assert_not date_request.key?("user_id")

    find("#classFilterBtn").click
    within "#classDropdown" do
      check "Outpatient / Emergency"
      click_button "Apply"
    end
    assert_selector "#ua-trending h3", text: "Margin Per Unit"
    assert_chart_data("#ua-trend-4 canvas", "Total", [ 10.25, 30 ])
  end

  private

  def assert_chart_data(selector, series_name, expected)
    values = nil
    Timeout.timeout(15) do
      loop do
        values = page.evaluate_script(<<~JS)
          (function () {
            if (!window.Chart) return null;
            const canvas = document.querySelector(#{selector.to_json});
            const chart = canvas && Chart.getChart(canvas);
            if (!chart) return null;
            const series = chart.data.datasets.find((item) => item.label === #{series_name.to_json});
            return series ? series.data : null;
          })()
        JS
        break if values
        sleep 0.2
      end
    end
    assert_equal expected, values.map(&:to_f)
  end
end
