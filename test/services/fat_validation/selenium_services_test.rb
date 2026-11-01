# frozen_string_literal: true

require "test_helper"

class FatValidation::SeleniumServicesTest < ActiveSupport::TestCase
  setup do
    @previous = ENV["FAT_TEAM_147_PASSWORD"]
    ENV["FAT_TEAM_147_PASSWORD"] = "selenium-secret"
    @environment = FatValidation::FatEnvironment.new(environment: "staging", team_id: "147")
  end

  teardown do
    ENV["FAT_TEAM_147_PASSWORD"] = @previous
  end

  test "chrome opens visibly and is left open after the driver quits" do
    options = FatValidation::Selenium::SeleniumRunner.chrome_options

    assert_equal true, options.options[:detach]
    assert_not_includes options.options[:args], "--headless"
    assert_not_includes options.options[:args], "--headless=new"

    remote = FatValidation::Selenium::SeleniumRunner.chrome_options(visible: false)
    assert_includes remote.options[:args], "--headless=new"
  end

  test "login submits the session form and fails closed without leaking the password" do
    driver = LoginDouble.new(succeed: false)
    handler = FatValidation::Selenium::AuthenticationHandler.new(driver, @environment, wait_seconds: 0.2)

    error = assert_raises(FatValidation::AuthenticationError) do
      handler.login
    end

    assert_equal "https://stg-savings.inpharmd.ai/login", driver.visits.first
    assert_equal "selenium-secret", driver.values["password"]
    assert_not_includes error.message, "selenium-secret"
    assert_match "team 147", error.message
  end

  test "login waits until the browser leaves the login page" do
    driver = LoginDouble.new(succeed: true)
    FatValidation::Selenium::AuthenticationHandler.new(driver, @environment, wait_seconds: 1).login

    assert_equal "https://stg-savings.inpharmd.ai/overview", driver.current_url
    assert driver.submitted
  end

  test "extractor reads drug names, opportunity text, and the quarter from the table" do
    driver = ExtractDouble.new(
      "accounting_period_id" => 8,
      "rows" => [ { "generic_group" => "Bevacizumab", "opportunity_text" => "$741,544" } ]
    )

    overview = FatValidation::Selenium::FrontendExtractor.new(driver, @environment, wait_seconds: 1).extract_overview

    assert_equal 8, overview.accounting_period_id
    assert_equal "Bevacizumab", overview.rows.first.generic_group
    assert_equal 741_544, overview.rows.first.actual_value
    assert_includes driver.script, "#overview-drug-table"
    assert_includes driver.script, ".fa-drug-name"
    assert_includes driver.script, ".fa-opp-cell__amount"
  end

  test "extractor reports an empty overview table" do
    driver = ExtractDouble.new("accounting_period_id" => 8, "rows" => [])

    assert_raises(FatValidation::EmptyReportError) do
      FatValidation::Selenium::FrontendExtractor.new(driver, @environment, wait_seconds: 1).extract_overview
    end
  end

  test "highlighter only adds pass and fail styles" do
    driver = HighlightDouble.new
    FatValidation::Selenium::FrontendHighlighter.new(driver).apply([
      { generic_group: "Bevacizumab", status: "PASS" },
      { generic_group: "Rituximab", status: "FAIL" }
    ])

    script, json = driver.args
    assert_includes script, "#overview-drug-table"
    assert_includes script, ".fa-opp-cell__amount"
    assert_includes script, "setProperty('background-color'"
    assert_includes script, "#16a34a"
    assert_includes script, "#dc2626"
    assert_not_includes script, ".click("
    assert_not_includes script, ".submit("
    payload = JSON.parse(json)
    assert_equal "PASS", payload.first["status"]
  end

  class LoginDouble
    attr_reader :visits, :values, :submitted
    attr_accessor :current_url

    def initialize(succeed:)
      @succeed = succeed
      @current_url = "about:blank"
      @visits = []
      @values = {}
      @submitted = false
    end

    def navigate
      driver = self
      Object.new.tap { |nav| nav.define_singleton_method(:to) { |url| driver.visit(url) } }
    end

    def visit(url)
      @visits << url
      @current_url = url
    end

    def find_elements(*)
      []
    end

    def find_element(id: nil, css: nil, xpath: nil)
      driver = self
      Object.new.tap do |element|
        element.define_singleton_method(:clear) {}
        element.define_singleton_method(:send_keys) { |value| driver.values[id.to_s] = value }
        element.define_singleton_method(:click) do
          driver.instance_variable_set(:@submitted, true)
          driver.current_url = "https://stg-savings.inpharmd.ai/overview" if driver.instance_variable_get(:@succeed)
        end
      end
    end
  end

  class ExtractDouble
    attr_reader :script
    attr_accessor :current_url

    def initialize(payload)
      @payload = payload
      @current_url = "https://stg-savings.inpharmd.ai/overview"
    end

    def navigate
      driver = self
      Object.new.tap { |nav| nav.define_singleton_method(:to) { |url| driver.current_url = url } }
    end

    def find_elements(*)
      [ Object.new ]
    end

    def execute_script(script)
      @script = script
      @payload
    end
  end

  class HighlightDouble
    attr_reader :args

    def execute_script(script, json)
      @args = [ script, json ]
    end
  end
end
