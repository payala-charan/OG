# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class FatValidationJobTest < ActiveSupport::TestCase
  test "runs once and does not repeat a finished validation" do
    run = FatValidationRun.create!(
      team_id: "147",
      environment: "staging",
      report_type: "overview",
      data_source: "database",
      status: :pending
    )
    calls = 0
    runner = Object.new
    runner.define_singleton_method(:call) do
      calls += 1
      run.update!(status: :completed, completed_at: Time.current)
    end

    FatValidation::Runner.stub(:new, ->(_run, visible: true) { runner }) do
      FatValidationJob.perform_now(run.id)
      FatValidationJob.perform_now(run.id)
    end

    assert_equal 1, calls
  end

  test "a failure in one run does not change another run" do
    first = FatValidationRun.create!(team_id: "147", environment: "local", report_type: "overview", data_source: "database", status: :pending)
    second = FatValidationRun.create!(team_id: "198", environment: "local", report_type: "overview", data_source: "database", status: :completed, completed_at: Time.current, passed_records: 3)

    failing = Object.new
    failing.define_singleton_method(:call) { raise "boom" }

    assert_raises(RuntimeError) do
      FatValidation::Runner.stub(:new, ->(_run, visible: true) { failing }) do
        FatValidationJob.perform_now(first.id)
      end
    end

    assert second.reload.completed?
    assert_equal 3, second.passed_records
  end
end
