# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class UtilizationAnalytics::ClientTest < ActiveSupport::TestCase
  test "loads analytics with GET and repeated filter params" do
    captured = nil
    response = Struct.new(:code, :body).new("200", %({"mode":"filters","message":null}))
    http = Object.new
    http.define_singleton_method(:request) do |request|
      captured = request
      response
    end

    payload = with_base_url("https://analytics.example") do
      Net::HTTP.stub(:start, ->(*args, **kwargs, &block) {
        @http_args = [ args, kwargs ]
        block.call(http)
      }) do
        UtilizationAnalytics::Client.new.fetch(
          "team_id" => "209",
          "group" => "Filgrastim",
          "hospital_names" => [ "Main Campus", "East" ]
        )
      end
    end

    assert_equal "filters", payload["mode"]
    assert_equal [ "analytics.example", 443 ], @http_args[0]
    assert_equal true, @http_args[1][:use_ssl]
    assert_equal "GET", captured.method
    query = URI.decode_www_form(captured.path.split("?", 2).last)
    assert_includes captured.path, "/api/utilization_analytics"
    assert_equal [ [ "team_id", "209" ], [ "group", "Filgrastim" ] ], query.first(2)
    assert_equal [ "Main Campus", "East" ], query.select { |key, _| key == "hospital_names[]" }.map(&:last)
    assert_equal "application/json", captured["Accept"]
  end

  test "posts a long filter list" do
    captured = nil
    response = Struct.new(:code, :body).new("200", %({"mode":"filters"}))
    http = Object.new
    http.define_singleton_method(:request) do |request|
      captured = request
      response
    end

    names = Array.new(40) { |index| "Hospital #{index} #{'x' * 40}" }
    with_base_url("http://analytics.example") do
      Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
        UtilizationAnalytics::Client.new.fetch("team_id" => "209", "hospital_names" => names)
      end
    end

    assert_equal "POST", captured.method
    assert_equal "/api/utilization_analytics", captured.path
    assert_includes captured.body, "team_id=209"
    assert_includes captured.body, "hospital_names%5B%5D="
  end

  test "unauthorized uses the payload error" do
    error = capture_error("401", %({"error":"Unauthorized"}))

    assert_instance_of UtilizationAnalytics::Client::Unauthorized, error
    assert_equal "Unauthorized", error.message
  end

  test "invalid dates use the payload error" do
    error = capture_error("422", %({"error":"start_date is invalid"}))

    assert_instance_of UtilizationAnalytics::Client::InvalidParams, error
    assert_equal "start_date is invalid", error.message
    assert_equal "start_date is invalid", error.payload["error"]
  end

  test "a refused connection stays on this side of the API" do
    error = assert_raises(UtilizationAnalytics::Client::Error) do
      with_base_url("http://analytics.example") do
        Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) {
          raise Errno::ECONNREFUSED
        }) do
          UtilizationAnalytics::Client.new.fetch("team_id" => "209")
        end
      end
    end

    assert_match "Could not reach utilization analytics", error.message
  end

  private

  def capture_error(code, body)
    response = Struct.new(:code, :body).new(code, body)
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }
    with_base_url("http://analytics.example") do
      Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
        UtilizationAnalytics::Client.new.fetch("team_id" => "209")
      end
    end
  rescue UtilizationAnalytics::Client::Error => error
    error
  end

  def with_base_url(url)
    previous = ENV["BASE_URL"]
    ENV["BASE_URL"] = url
    yield
  ensure
    ENV["BASE_URL"] = previous
  end
end
