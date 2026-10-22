# frozen_string_literal: true

require "test_helper"

class UtilizationAnalytics::QueryTest < ActiveSupport::TestCase
  test "an unapplied request sends only the default team" do
    query = UtilizationAnalytics::Query.build(team_id: nil, params: {}, applied: false)

    assert_equal({ "team_id" => "209" }, query)
    assert_not query.key?("user_id")
  end

  test "only the listed team ids are sent" do
    listed = UtilizationAnalytics::Query.build(team_id: "198", params: {}, applied: false)
    unknown = UtilizationAnalytics::Query.build(team_id: "999", params: {}, applied: false)

    assert_equal "198", listed["team_id"]
    assert_equal "209", unknown["team_id"]
  end

  test "quarter mode keeps the shared filters and leaves months and dates off the request" do
    query = build(period_kind: "quarter", trend_grain: "month")

    assert_equal "quarter", query["time_period"]
    assert_equal "Quarter 4 2025", query["quarter_name1"]
    assert_equal "Quarter 1 2026", query["quarter_name2"]
    assert_equal "Filgrastim", query["group"]
    assert_equal "Outpatient", query["charge_class"]
    assert_equal [ "Main", "East" ], query["hospital_names"]
    assert_equal [ "Aetna" ], query["payor_names"]
    assert_equal "147", query["team_id"]
    assert_not query.key?("data_month1")
    assert_not query.key?("start_date")
    assert_not query.key?("user_id")
  end

  test "month mode sends month names even when quarter names are still in the form" do
    query = build(period_kind: "month")

    assert_equal "month", query["time_period"]
    assert_equal "October 2025", query["data_month1"]
    assert_equal "November 2025", query["data_month2"]
    assert_not query.key?("quarter_name1")
    assert_not query.key?("start_date")
  end

  test "date range sends the trend grain and dates" do
    query = build(period_kind: "date_range", trend_grain: "month")

    assert_equal "month", query["time_period"]
    assert_equal "2025-10-01", query["start_date"]
    assert_equal "2026-01-31", query["end_date"]
    assert_not query.key?("quarter_name1")
    assert_not query.key?("data_month1")
  end

  test "quarter wins when a request has every period and no explicit kind" do
    params = filter_params
    params.delete(:period_kind)

    assert_equal "quarter", UtilizationAnalytics::Query.period_kind(params)
    query = UtilizationAnalytics::Query.build(team_id: "198", params: params, applied: true)
    assert_equal "Quarter 4 2025", query["quarter_name1"]
    assert_not query.key?("data_month1")
    assert_not query.key?("start_date")
  end

  private

  def build(extra)
    UtilizationAnalytics::Query.build(team_id: "147", params: filter_params.merge(extra), applied: true)
  end

  def filter_params
    {
      period_kind: "quarter",
      group: "Filgrastim",
      quarter_name1: "Quarter 4 2025",
      quarter_name2: "Quarter 1 2026",
      data_month1: "October 2025",
      data_month2: "November 2025",
      start_date: "2025-10-01",
      end_date: "2026-01-31",
      charge_class: "Outpatient",
      hospital_names: [ "Main", "", "East" ],
      payor_names: [ "Aetna" ],
      trend_grain: "quarter"
    }
  end
end
