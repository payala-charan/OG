# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class UtilizationAnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "analytics-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
    @recorder = Recorder.new(filters_payload)
  end

  test "requires login" do
    get utilization_analytics_path

    assert_redirected_to login_path
  end

  test "first load asks for the default team and fills the controls" do
    log_in
    with_client do
      get utilization_analytics_path
    end

    assert_response :success
    assert_equal({ "team_id" => "209" }, @recorder.query)
    assert_not @recorder.query.key?("user_id")
    assert_select "select#teamSelect option", text: "198"
    assert_select "select#teamSelect option[selected]", text: "209"
    assert_select "select#teamSelect option", text: "147"
    assert_select ".ua-banner--info", text: "Select a group and two periods to view the comparison."
    assert_select "select#group option", text: "PEGFILGRASTIM"
    assert_select "select#group option", text: "Filgrastim"
    assert_select "select#quarter_name1 option", text: "Quarter 2 2026"
    assert_select "select#quarter_name1 option[selected]", text: "Quarter 4 2025"
    assert_select "select#quarter_name2 option[selected]", text: "Quarter 1 2026"
    assert_select "select#data_month1 option", text: "September 2025"
    assert_select "select#data_month1 option", text: "January 2027"
    assert_select "select#data_month1 option", text: "October 2025"
    assert_select "input[name=charge_class][value=Outpatient][checked]"
    assert_select "input[name='hospital_names[]'][value=?]", "Main Campus"
    assert_select "input[name='payor_names[]'][value=?]", "Aetna"
    assert_select "#ua-validate-btn", count: 0
    assert_select "#quarter-compare-btn[disabled]"
    assert_select "#trendBtn[disabled]"
    assert_select "#ua-section-total_units", count: 0
  end

  test "quarter comparison renders display cells, proof, and api chart series" do
    log_in
    @recorder.result = quarter_payload
    with_client do
      get utilization_analytics_path, params: {
        analytics_request: "1",
        period_kind: "quarter",
        group: "Filgrastim",
        quarter_name1: "Quarter 4 2025",
        quarter_name2: "Quarter 1 2026",
        data_month1: "October 2025",
        data_month2: "November 2025",
        start_date: "2025-10-01",
        end_date: "2026-01-31",
        charge_class: "Outpatient",
        hospital_names: [ "Main Campus" ],
        payor_names: [ "Aetna" ],
        team_id: "198"
      }
    end

    assert_response :success
    assert_equal "quarter", @recorder.query["time_period"]
    assert_equal "Filgrastim", @recorder.query["group"]
    assert_equal [ "Main Campus" ], @recorder.query["hospital_names"]
    assert_equal "198", @recorder.query["team_id"]
    assert_not @recorder.query.key?("data_month1")
    assert_not @recorder.query.key?("start_date")
    assert_not @recorder.query.key?("user_id")

    assert_select "#ua-section-total_units th", text: "Quarter 4 2025"
    assert_select "#ua-section-total_units td", text: "10 units"
    assert_select "#ua-section-total_units td", text: "API GRAND"
    assert_select "#ua-section-total_units .ua-proof", text: /PROOF-LINE/
    assert_select "#ua-section-total_units .ua-proof", text: /API-WEIGHT/
    assert_select "#ua-section-margin_percent_of_cost td", text: "PCT-DIFF"
    assert_select "#ua-section-margin_percent_of_cost td", text: "NO-TOTAL", count: 0
    assert_select "#ua-section-total_margin", count: 0
    assert_match "Quarter 1 2024", response.body
    assert_match "10.25", response.body
    assert_match "Expense Difference", response.body
    assert_match "150.5", response.body
    assert_match "Margin Improvement Infliximab", response.body
    assert_select "#ua-validate-btn", text: /Verification \/ Validation/
    embedded = response.body[/<script type="application\/json" id="ua-analytics-payload">(.*?)<\/script>/m, 1]
    assert JSON.parse(embedded).dig("comparison", "total_units").is_a?(Hash)
    assert_select "#ua-section-total_units td", text: "111111", count: 0
    assert_select "#ua-section-total_units td", text: "222222", count: 0
    assert_no_match(/111141/, response.body)
    assert_includes response.body, "Zarxio &lt;b&gt;"
  end

  test "cms total units proof renders as a grouped quarter sheet" do
    log_in
    payload = quarter_payload
    payload["comparison"]["total_units"]["proof"] = cms_units_proof
    payload["comparison"]["product_cost"] = section(
      "Total Product Cost",
      [ "Brand", "Quarter 1 2026", "Quarter 2 2026", "Total", "Difference" ]
    ).merge("proof" => product_cost_proof)
    @recorder.result = payload
    with_client do
      get utilization_analytics_path, params: {
        analytics_request: "1",
        period_kind: "quarter",
        group: "BEVACIZUMAB",
        quarter_name1: "Quarter 1 2026",
        quarter_name2: "Quarter 2 2026"
      }
    end

    assert_response :success
    assert_select "#ua-section-total_units .ua-proof h3", text: "Calculation proof — CMS Total Units"
    assert_select "#ua-section-total_units .ua-proof", text: /Outpatient \+ Emergency/
    assert_select "#ua-section-total_units .ua-proof th", text: "Quarter 4 2025"
    assert_select "#ua-section-total_units .ua-proof th", text: "Quarter 1 2026"
    assert_select "#ua-section-total_units .ua-proof th", text: "Outpatient"
    assert_select "#ua-section-total_units .ua-proof th", text: "Emergency"
    assert_select "#ua-section-total_units .ua-proof th", text: "Inpatient"
    assert_select "#ua-section-total_units .ua-proof th", text: "Inpatient (rows)"
    assert_select "#ua-section-total_units .ua-proof th", text: "OP+EM (in table)"
    assert_select "#ua-section-total_units .ua-proof td", text: "AVASTIN"
    assert_select "#ua-section-total_units .ua-proof td", text: "3550.0"
    assert_select "#ua-section-total_units .ua-proof", text: /19108\.6/
    assert_select "#ua-section-total_units .ua-proof", text: /Σ brand CMS units \(OP\+EM\)/
    assert_select "#ua-section-total_units .ua-proof", text: /PROOF-LINE/, count: 0
    assert_select "#ua-section-product_cost .ua-proof h3", text: "Calculation proof — Total Product Cost"
    assert_select "#ua-section-product_cost .ua-proof th", text: "Total cost (in table)"
    assert_select "#ua-section-product_cost .ua-proof", text: /\$1,250\.00/
  end

  test "date range hides comparison tables and plots the charts the api returned" do
    log_in
    @recorder.result = date_range_payload
    with_client do
      get utilization_analytics_path, params: {
        analytics_request: "1",
        period_kind: "date_range",
        trend_grain: "quarter",
        group: "Filgrastim",
        start_date: "2025-10-01",
        end_date: "2026-03-31",
        quarter_name1: "Quarter 4 2025",
        quarter_name2: "Quarter 1 2026"
      }
    end

    assert_response :success
    assert_equal "2025-10-01", @recorder.query["start_date"]
    assert_equal "2026-03-31", @recorder.query["end_date"]
    assert_equal "209", @recorder.query["team_id"]
    assert_not @recorder.query.key?("user_id")
    assert_not @recorder.query.key?("quarter_name1")
    assert_select ".ua-page table.ua-table", count: 0
    assert_select "#ua-chart-total_units"
    assert_select "#ua-chart-drug_spend"
    assert_select "#ua-trending"
    assert_select ".ua-grain", text: "quarterly"
    %w[Units Total\ Product\ Cost Product\ Cost\ Per\ Unit Total\ Margin Margin\ Per\ Unit].each do |title|
      assert_select "#ua-trending h3", text: title
    end
  end

  test "inpatient date range keeps units cost and drug spend" do
    log_in
    @recorder.result = inpatient_payload
    with_client do
      get utilization_analytics_path, params: {
        analytics_request: "1",
        period_kind: "date_range",
        group: "Filgrastim",
        start_date: "2025-10-01",
        end_date: "2026-03-31",
        charge_class: "Inpatient"
      }
    end

    assert_response :success
    assert_equal "Inpatient", @recorder.query["charge_class"]
    assert_select "#classFilterBtn", text: /Inpatient/
    assert_select "#ua-chart-total_units"
    assert_select "#ua-chart-drug_spend"
    assert_select "#ua-section-total_margin", count: 0
    assert_select "#ua-chart-margin_improvement", count: 0
    assert_select "#ua-trending h3", text: "Units"
    assert_select "#ua-trending h3", text: "Total Margin", count: 0
    assert_select "#ua-trending h3", text: "Margin Per Unit", count: 0
  end

  test "unknown user shows the unauthorized payload" do
    log_in
    @recorder.error = UtilizationAnalytics::Client::Unauthorized.new("Unauthorized")
    with_client do
      get utilization_analytics_path
    end

    assert_response :unauthorized
    assert_select ".ua-banner--error", text: "Unauthorized"
  end

  test "invalid dates show the payload error" do
    log_in
    @recorder.error = UtilizationAnalytics::Client::InvalidParams.new(
      "start_date is invalid",
      { "error" => "start_date is invalid", "filters" => filters_payload["filters"] }
    )
    with_client do
      get utilization_analytics_path, params: {
        analytics_request: "1",
        period_kind: "date_range",
        group: "Filgrastim",
        start_date: "not-a-date",
        end_date: "2026-01-31"
      }
    end

    assert_response :unprocessable_entity
    assert_select ".ua-banner--error", text: "start_date is invalid"
    assert_select "select#group option", text: "Filgrastim"
  end

  private

  def log_in
    post login_path, params: { email: @user.email, password: "password123" }
  end

  def with_client
    UtilizationAnalytics::Client.stub(:new, @recorder) do
      yield
    end
  end

  def filters_payload
    {
      "time_period" => "quarter",
      "charge_class" => "Outpatient",
      "inpatient" => false,
      "mode" => "filters",
      "message" => nil,
      "filters" => {
        "generic_name_groups" => [ "Filgrastim", "Infliximab" ],
        "quarters" => [ "Quarter 4 2025", "Quarter 1 2026" ],
        "data_months" => [ "October 2025", "November 2025" ],
        "hospital_names" => [ "Main Campus", "East" ],
        "payor_names" => [ "Aetna" ],
        "charge_classes" => [ "Outpatient", "Inpatient" ],
        "selected" => {
          "group" => nil,
          "time_period" => "quarter",
          "quarter_name1" => "Quarter 4 2025",
          "quarter_name2" => "Quarter 1 2026",
          "charge_class" => "Outpatient",
          "hospital_names" => [],
          "payor_names" => []
        },
        "message" => "Select a group and two periods to view the comparison."
      },
      "comparison" => nil,
      "trending" => nil
    }
  end

  def quarter_payload
    filters_payload.merge(
      "mode" => "quarter",
      "message" => nil,
      "filters" => filters_payload["filters"].merge("message" => nil),
      "comparison" => {
        "periods" => { "baseline" => "Quarter 4 2025", "comparator" => "Quarter 1 2026" },
        "tables_visible" => true,
        "total_units" => section(
          "Total Units",
          [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ],
          chart_title: "Total Units"
        ),
        "total_margin" => section("Total Margin", [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ]).merge("visible" => false, "chart" => { "visible" => false }),
        "margin_percent_of_cost" => {
          "title" => "Margin Percent of Cost",
          "visible" => true,
          "columns" => [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Difference" ],
          "rows" => [
            {
              "brand" => "Inflectra",
              "baseline" => 1,
              "comparator" => 2,
              "total" => 999,
              "difference" => 3,
              "baseline_display" => "1%",
              "comparator_display" => "2%",
              "total_display" => "NO-TOTAL",
              "difference_display" => "PCT-DIFF"
            }
          ],
          "grand_total" => {
            "brand" => "Total",
            "total_display" => "NO-TOTAL",
            "difference_display" => "PCT-GRAND"
          },
          "chart" => {
            "title" => "Margin Improvement Infliximab",
            "visible" => true,
            "y_axis" => "Percent",
            "x_axis" => "Margin",
            "series" => [ { "name" => "Baseline", "data" => { "MARGIN" => 20.0 } } ]
          },
          "proof" => nil
        },
        "drug_spend" => {
          "title" => "Drug Spend",
          "visible" => true,
          "y_axis" => "Dollars",
          "x_axis" => "Drug Spend",
          "series" => [
            { "name" => "Baseline", "data" => { "Drug Spend" => 100.0 } },
            { "name" => "Expense Difference", "data" => { "Drug Spend" => 150.5 } }
          ]
        },
        "margin_improvement" => {
          "title" => "Margin Improvement Infliximab",
          "visible" => true,
          "series" => [ { "name" => "Comparator", "data" => { "MARGIN" => 20.0 } } ]
        }
      }
    )
  end

  def date_range_payload
    filters_payload.merge(
      "mode" => "date_range",
      "time_period" => "quarter",
      "comparison" => {
        "tables_visible" => false,
        "total_units" => section(
          "Total Units",
          [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ],
          chart_title: "Total Units",
          column: false
        ),
        "total_margin" => { "title" => "Total Margin", "visible" => true, "chart" => { "title" => "Total Margin", "visible" => true, "series" => [] } },
        "drug_spend" => quarter_payload.dig("comparison", "drug_spend")
      },
      "trending" => {
        "visible" => true,
        "grain" => "quarterly",
        "charts" => [
          "Units",
          "Total Product Cost",
          "Product Cost Per Unit",
          "Total Margin",
          "Margin Per Unit"
        ].map { |title| trend_chart(title) }
      }
    )
  end

  def inpatient_payload
    payload = date_range_payload.merge(
      "charge_class" => "Inpatient",
      "inpatient" => true,
      "comparison" => date_range_payload["comparison"].merge(
        "total_margin" => { "title" => "Total Margin", "visible" => false, "chart" => { "visible" => false } },
        "margin_per_unit" => { "title" => "Margin Per Unit", "visible" => false, "chart" => { "visible" => false } },
        "margin_percent_of_cost" => { "title" => "Margin Percent of Cost", "visible" => false, "chart" => { "visible" => false } },
        "margin_improvement" => { "title" => "Margin Improvement Infliximab", "visible" => false }
      ),
      "trending" => {
        "visible" => true,
        "grain" => "quarterly",
        "charts" => [ "Units", "Total Product Cost", "Product Cost Per Unit" ].map { |title| trend_chart(title) }
      }
    )
    payload["filters"]["selected"] = payload["filters"]["selected"].merge("charge_class" => "Inpatient")
    payload
  end

  def section(title, columns, total_display: "API GRAND", chart_title: title, column: false)
    {
      "title" => title,
      "visible" => true,
      "columns" => columns,
      "rows" => [
        {
          "brand" => "Zarxio <b>",
          "baseline" => 111111,
          "comparator" => 30,
          "total" => 222222,
          "difference" => 20,
          "baseline_display" => "10 units",
          "comparator_display" => "30 units",
          "total_display" => "40 units",
          "difference_display" => "20 units"
        }
      ],
      "grand_total" => {
        "brand" => "Total",
        "baseline" => 1,
        "comparator" => 2,
        "total" => 3,
        "difference" => 4,
        "baseline_display" => "B",
        "comparator_display" => "C",
        "total_display" => total_display,
        "difference_display" => "D"
      },
      "chart" => {
        "title" => chart_title,
        "visible" => true,
        "y_axis" => "Units",
        "x_axis" => "Quarter",
        "series" => [
          { "name" => "Zarxio <b>", "data" => column ? { "Drug Spend" => 10.25 } : [ [ "Quarter 1 2024", 10.25 ], [ "Quarter 2 2024", 30.0 ] ] },
          { "name" => "Total", "data" => column ? { "Drug Spend" => 10.25 } : [ [ "Quarter 1 2024", 10.25 ], [ "Quarter 2 2024", 30.0 ] ] }
        ]
      },
      "proof" => { "steps" => [ "PROOF-LINE" ], "weight" => "API-WEIGHT" }
    }
  end

  def cms_units_proof
    {
      "charge_classes" => [ "Outpatient", "Emergency", "Inpatient" ],
      "show_inpatient_row_count" => true,
      "rows" => {
        "AVASTIN" => {
          "q1" => { "Outpatient" => 3550.0, "Emergency" => 0, "Inpatient" => 0 },
          "q2" => { "Outpatient" => 3290.2, "Emergency" => 0, "Inpatient" => 0 },
          "q1_inpatient_row_count" => 0,
          "q2_inpatient_row_count" => 0,
          "q1_table_total" => 3550.0,
          "q2_table_total" => 3290.2
        }
      },
      "grand_totals" => {
        "q1" => { "cms_units" => 19_108.6 },
        "q2" => { "cms_units" => 17_586.1 }
      }
    }
  end

  def product_cost_proof
    {
      "rows" => {
        "AVASTIN" => {
          "q1" => {
            "cms_total_units_rounded" => 3550.0,
            "product_cost_per_unit_rounded" => 12.5,
            "total_product_cost_computed" => 1250.0,
            "total_product_cost_in_table" => 1250.0
          },
          "q2" => {
            "cms_total_units_rounded" => 3290.2,
            "product_cost_per_unit_rounded" => 12.5,
            "total_product_cost_computed" => 1100.0,
            "total_product_cost_in_table" => 1100.0
          }
        }
      },
      "grand_totals" => {
        "q1" => { "cms_units" => 3550.0, "product_cost_per_unit" => 12.5, "product_cost" => 1250.0 },
        "q2" => { "cms_units" => 3290.2, "product_cost_per_unit" => 12.5, "product_cost" => 1100.0 }
      }
    }
  end

  def trend_chart(title)
    {
      "title" => title,
      "y_axis" => title,
      "x_axis" => "Quarter",
      "series" => [ { "name" => "Total", "data" => [ [ "Quarter 1 2024", 10.25 ] ] } ]
    }
  end

  class Recorder
    attr_reader :query
    attr_accessor :result, :error

    def initialize(result)
      @result = result
    end

    def fetch(query)
      @query = query
      raise error if error

      result
    end
  end
end
