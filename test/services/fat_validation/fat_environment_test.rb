# frozen_string_literal: true

require "test_helper"

class FatValidation::FatEnvironmentTest < ActiveSupport::TestCase
  setup do
    @previous = ENV["FAT_TEAM_209_PASSWORD"]
    ENV["FAT_TEAM_209_PASSWORD"] = "team-209-secret"
  end

  teardown do
    ENV["FAT_TEAM_209_PASSWORD"] = @previous
  end

  test "uses allowlisted origins and ignores a path pasted into the url" do
    previous = ENV["FAT_STAGING_URL"]
    ENV["FAT_STAGING_URL"] = "https://stg-savings.inpharmd.ai/overview"
    environment = FatValidation::FatEnvironment.new(environment: "staging", team_id: "209")

    assert_equal "https://stg-savings.inpharmd.ai", environment.base_url
    assert_equal "https://stg-savings.inpharmd.ai/login", environment.login_url
    assert_equal "https://stg-savings.inpharmd.ai/overview", environment.overview_url
  ensure
    ENV["FAT_STAGING_URL"] = previous
  end

  test "rejects environments outside the allowlist" do
    error = assert_raises(FatValidation::ConfigurationError) do
      FatValidation::FatEnvironment.new(environment: "https://evil.example", team_id: "209")
    end
    assert_equal "Choose Local, Staging, or Production.", error.message
  end

  test "reads the team password from the environment and hides it from inspect" do
    environment = FatValidation::FatEnvironment.new(environment: "production", team_id: "209")

    assert_equal "steve+charles@inpharmd.com", environment.credentials[:email]
    assert_equal "team-209-secret", environment.credentials[:password]
    assert_not_includes environment.inspect, "team-209-secret"
  end

  test "reports a missing password without inventing one" do
    ENV["FAT_TEAM_209_PASSWORD"] = ""

    error = assert_raises(FatValidation::ConfigurationError) do
      FatValidation::FatEnvironment.new(environment: "local", team_id: "209").credentials
    end
    assert_match "FAT_TEAM_209_PASSWORD", error.message
  end
end
