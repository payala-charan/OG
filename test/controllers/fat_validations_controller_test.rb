# frozen_string_literal: true

require "test_helper"

class FatValidationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @previous_password = ENV["FAT_TEAM_147_PASSWORD"]
    ENV["FAT_TEAM_147_PASSWORD"] = "controller-test-password"
    @user = User.create!(email: "fat-ui-#{SecureRandom.hex(4)}@example.com", password: "password")
    post login_path, params: { email: @user.email, password: "password" }
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_adapter
    ENV["FAT_TEAM_147_PASSWORD"] = @previous_password
  end

  test "guests are sent to login" do
    delete logout_path
    get fat_validations_path
    assert_redirected_to login_path
  end

  test "database overview enqueues a run for the selected team" do
    assert_difference -> { FatValidationRun.count }, 1 do
      assert_enqueued_with(job: FatValidationJob) do
        post fat_validations_path, params: {
          environment: "staging",
          team_id: "147",
          report_type: "overview",
          data_source: "database"
        }
      end
    end

    run = FatValidationRun.order(:id).last
    assert_redirected_to fat_validations_path(run_id: run.id)
    assert_equal "147", run.team_id
    assert_equal "staging", run.environment
    assert_equal "overview", run.report_type
    assert_equal "database", run.data_source
    assert run.pending?
    assert_equal @user, run.user
  end

  test "an ngrok host does not open a browser on the server display" do
    assert_equal true, FatValidationsController.local_browser?("localhost")
    assert_equal true, FatValidationsController.local_browser?("127.0.0.1")
    assert_equal false, FatValidationsController.local_browser?("vowel-retaining-doctrine.ngrok-free.dev")
  end

  test "excel is rejected until the sheet mapping exists" do
    assert_no_difference -> { FatValidationRun.count } do
      post fat_validations_path, params: {
        environment: "staging",
        team_id: "147",
        report_type: "overview",
        data_source: "excel"
      }
    end

    assert_redirected_to fat_validations_path
    assert_match "Excel upload is not configured", flash[:alert]
  end

  test "unknown teams and reports are rejected" do
    post fat_validations_path, params: {
      environment: "staging",
      team_id: "298",
      report_type: "overview",
      data_source: "database"
    }
    assert_redirected_to fat_validations_path
    assert_match "Choose a team", flash[:alert]

    post fat_validations_path, params: {
      environment: "https://example.com",
      team_id: "147",
      report_type: "overview",
      data_source: "database"
    }
    assert_match "Local, Staging, or Production", flash[:alert]
  end

  test "show returns status json and hides another user's run" do
    run = @user.fat_validation_runs.create!(
      team_id: "209",
      environment: "production",
      report_type: "overview",
      data_source: "database",
      status: :pending,
      progress_message: "Queued"
    )
    get fat_validation_path(run, format: :json)
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "pending", body["status"]
    assert_equal "209", body["team_id"]

    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password")
    foreign = other.fat_validation_runs.create!(
      team_id: "198",
      environment: "local",
      report_type: "overview",
      data_source: "database",
      status: :pending
    )
    get fat_validation_path(foreign)
    assert_response :not_found
  end
end
