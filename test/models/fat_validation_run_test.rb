# frozen_string_literal: true

require "test_helper"

class FatValidationRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "fat-run-#{SecureRandom.hex(4)}@example.com", password: "password")
  end

  test "requires an allowlisted team, environment, report, and source" do
    run = FatValidationRun.new(user: @user, team_id: "999", environment: "remote", report_type: "other", data_source: "api")

    assert_not run.valid?
    assert_includes run.errors[:team_id], "is not included in the list"
    assert_includes run.errors[:environment], "is not included in the list"
    assert_includes run.errors[:report_type], "is not included in the list"
    assert_includes run.errors[:data_source], "is not included in the list"
  end

  test "latest completed run is the newest one for that team, environment, and report" do
    older = create_run(status: :completed, completed_at: 2.days.ago)
    newer = create_run(status: :completed, completed_at: 1.hour.ago)
    create_run(status: :failed, completed_at: Time.current)
    create_run(status: :completed, completed_at: Time.current, environment: "production")

    found = FatValidationRun.latest_completed_for(team_id: "147", environment: "staging", report_type: "overview")

    assert_equal newer, found
    assert_not_equal older, found
  end

  test "keeps earlier results when another run is created" do
    first = create_run(status: :completed, completed_at: 1.day.ago)
    first.results.create!(column_name: "opportunity", status: "PASS", generic_group: "Bevacizumab", expected_value: 10, actual_value: 10, difference: 0)
    second = create_run(status: :completed, completed_at: Time.current)

    assert_equal 1, first.results.count
    assert_equal 0, second.results.count
  end

  private

  def create_run(status:, completed_at:, environment: "staging")
    FatValidationRun.create!(
      user: @user,
      team_id: "147",
      environment: environment,
      report_type: "overview",
      data_source: "database",
      status: status,
      completed_at: completed_at
    )
  end
end
