# frozen_string_literal: true

module FatValidation
  module Selenium
    # Opens a visible Chrome window on the machine running this process.
    # A finished validation keeps that window open. Quitting the driver also
    # stops ChromeDriver, which closes the window.
    class SeleniumRunner
      @open_drivers = []

      class << self
        attr_reader :open_drivers

        def retain(driver)
          return if driver.nil?

          @open_drivers << driver
        end
      end

      def initialize(visible: true)
        @visible = visible
      end

      def start
        options = self.class.chrome_options(visible: @visible)
        @driver = ::Selenium::WebDriver.for(:chrome, options: options)
        @driver.manage.timeouts.page_load = 90
        @driver.manage.timeouts.implicit_wait = 0
        @driver
      rescue ::Selenium::WebDriver::Error::WebDriverError => e
        raise BrowserError, "Could not open Chrome (#{e.class.name.demodulize})."
      end

      def focus
        return unless @driver

        @driver.switch_to.window(@driver.window_handles.last)
        @driver.manage.window.maximize
        @driver.execute_script("window.focus()")
        bring_to_front(@driver.current_url)
      rescue StandardError
        nil
      end

      # Keep the FAT window and its colors. Do not send quit.
      def leave_open
        return unless @driver

        focus
        self.class.retain(@driver)
        @left_open = true
        @driver = nil
      end

      def quit
        return if @left_open || @driver.nil?

        @driver.quit
      rescue StandardError
        nil
      ensure
        @driver = nil
      end

      def capture_png
        return unless @driver

        @driver.screenshot_as(:png)
      rescue StandardError
        nil
      end

      def self.chrome_options(visible: true)
        options = ::Selenium::WebDriver::Chrome::Options.new
        if visible
          options.add_argument("--start-maximized")
        else
          options.add_argument("--headless=new")
          options.add_argument("--window-size=1440,1600")
          options.add_argument("--hide-scrollbars")
        end
        options.add_option(:detach, true)
        options
      end

      private

      def bring_to_front(url)
        return unless RUBY_PLATFORM.include?("darwin")

        host = URI.parse(url.to_s).host.to_s.gsub(/[^A-Za-z0-9.\-]/, "")
        return if host.blank?

        system("osascript", "-e", <<~APPLESCRIPT)
          tell application "Google Chrome"
            activate
            repeat with w in windows
              try
                if URL of active tab of w contains "#{host}" then
                  set index of w to 1
                  exit repeat
                end if
              end try
            end repeat
          end tell
        APPLESCRIPT
      rescue StandardError
        nil
      end
    end
  end
end
