# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class FatValidation::RunnerTest < ActiveSupport::TestCase
  setup do
    @previous = ENV["FAT_TEAM_147_PASSWORD"]
    ENV["FAT_TEAM_147_PASSWORD"] = "runner-secret"
  end

  teardown do
    ENV["FAT_TEAM_147_PASSWORD"] = @previous
  end

  test "compares overview opportunity and leaves the FAT window open" do
    report = UtilizationAnalytics::Tables.utilization_reports.create!(
      team_id: "147",
      accounting_period_id: 8,
      category: nil,
      generic_name_group: "Bevacizumab"
    )
    UtilizationAnalytics::Tables.relation("invoice_conversions").create!(
      utilization_report_id: report.id,
      team_id: "147",
      conversion_type: "highest_margin",
      status: "individual",
      blended_conversion_margin_difference: 100.9
    )
    run = FatValidationRun.create!(
      team_id: "147",
      environment: "staging",
      report_type: "overview",
      data_source: "database",
      status: :pending
    )
    browser = BrowserDouble.new
    runner = FatValidation::Runner.new(run, browser: browser)
    highlighted = nil

    runner.stub(:authenticate, nil) do
      runner.stub(:extract, extracted(100)) do
        runner.stub(:highlight, ->(_driver, rows) { highlighted = rows }) do
          runner.call
        end
      end
    end

    assert run.reload.completed?
    assert_equal 8, run.accounting_period_id
    assert_equal 1, run.passed_records
    assert_equal 0, run.failed_records
    assert_equal "PASS", run.results.first.status
    assert_equal 100, run.results.first.expected_value.to_i
    assert_equal "PASS", highlighted.first[:status]
    assert_equal 0, browser.quit_calls
    assert browser.left_open
  end

  test "keeps saved rows when highlighting fails and redacts secrets" do
    run = FatValidationRun.create!(
      team_id: "147",
      environment: "local",
      report_type: "overview",
      data_source: "database",
      status: :pending
    )
    browser = BrowserDouble.new
    runner = FatValidation::Runner.new(run, browser: browser)

    runner.stub(:authenticate, ->(*) { raise FatValidation::AuthenticationError, "rejected runner-secret" }) do
      runner.call
    end

    assert run.reload.failed?
    assert_not_includes run.error_message, "runner-secret"
    assert_includes run.error_message, "[filtered]"
    assert_equal 1, browser.quit_calls
    assert_equal 0, run.results.count
  end

  private

  def extracted(amount)
    FatValidation::Selenium::FrontendExtractor::Overview.new(
      accounting_period_id: 8,
      rows: [
        FatValidation::Selenium::FrontendExtractor::DrugRow.new(
          generic_group: "Bevacizumab",
          actual_value: amount,
          raw_actual: "$#{amount}"
        )
      ]
    )
  end

  class BrowserDouble
    attr_reader :quit_calls

    def initialize
      @quit_calls = 0
    end

    attr_reader :left_open

    def start
      :driver
    end

    def focus
      nil
    end

    def leave_open
      @left_open = true
    end

    def capture_png
      nil
    end

    def quit
      @quit_calls += 1 unless @left_open
    end
  end
end
