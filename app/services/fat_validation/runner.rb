# frozen_string_literal: true

module FatValidation
  class Runner
    def initialize(run, browser: nil, visible: true)
      @run = run
      @visible = visible
      @browser = browser || Selenium::SeleniumRunner.new(visible: visible)
    end

    def call
      @run.update!(status: :running, started_at: Time.current, error_message: nil, progress_message: "Opening FAT")
      environment = FatEnvironment.new(environment: @run.environment, team_id: @run.team_id)
      raise Error, "Only Database source is available." unless @run.data_source == "database"
      raise Error, "Only the Overview report is available." unless @run.report_type == "overview"

      driver = @browser.start
      authenticate(driver, environment)
      extracted = extract(driver, environment)
      @run.update!(accounting_period_id: extracted.accounting_period_id, progress_message: "Calculating opportunity")

      expected = DataSources::DatabaseProcessor.new(
        run: @run,
        generic_groups: extracted.rows.map(&:generic_group)
      ).call
      comparisons = ValidationComparator.new.compare(actual_rows: extracted.rows, expected_rows: expected)
      ResultBuilder.new(@run).save!(comparisons)
      highlight(driver, comparisons)
      attach_screenshot
      @browser.leave_open if @visible
      @run.update!(progress_message: @visible ? "Highlighted in the FAT window" : "Colored FAT page is ready")
      Rails.logger.info("[FatValidation] run=#{@run.id} team=#{@run.team_id} env=#{@run.environment} passed=#{@run.passed_records} failed=#{@run.failed_records}")
    rescue StandardError => e
      @run.update!(
        status: :failed,
        error_message: safe_message(e),
        completed_at: @run.completed_at || Time.current,
        progress_message: "Failed"
      )
      Rails.logger.error("[FatValidation] run=#{@run.id} team=#{@run.team_id} env=#{@run.environment} failed")
    ensure
      @browser.quit
    end

    private

    def authenticate(driver, environment)
      Selenium::AuthenticationHandler.new(driver, environment).login
    end

    def extract(driver, environment)
      Selenium::FrontendExtractor.new(driver, environment).extract_overview
    end

    def highlight(driver, comparisons)
      Selenium::FrontendHighlighter.new(driver).apply(comparisons)
    end

    def attach_screenshot
      png = @browser.capture_png
      return if png.blank?

      io = StringIO.new(png)
      io.set_encoding(Encoding::BINARY)
      @run.highlight_screenshot.attach(
        io: io,
        filename: "fat-overview-#{@run.id}.png",
        content_type: "image/png"
      )
    rescue StandardError
      Rails.logger.error("[FatValidation] run=#{@run.id} screenshot failed")
    end

    def safe_message(error)
      text = "#{error.class.name.demodulize}: #{error.message}"
      FatEnvironment.secret_values.each do |secret|
        text = text.gsub(secret, "[filtered]")
      end
      text.truncate(500)
    end
  end
end
