# frozen_string_literal: true

module FatValidation
  module Selenium
    # Signs in through the FAT login form at /session.
    # The only submit is that login form. Credentials are not logged.
    class AuthenticationHandler
      def initialize(driver, environment, wait_seconds: 30)
        @driver = driver
        @environment = environment
        @wait_seconds = wait_seconds
      end

      def login
        @driver.navigate.to(@environment.login_url)
        dismiss_cookie_banner
        email, password = @environment.credentials.values_at(:email, :password)

        fill(id: "email", value: email)
        fill(id: "password", value: password)
        @driver.find_element(css: "form[action='/session'] button[type='submit']").click

        ::Selenium::WebDriver::Wait.new(timeout: @wait_seconds).until do
          !@driver.current_url.to_s.include?("/login")
        end
      rescue ::Selenium::WebDriver::Error::TimeoutError
        raise AuthenticationError, "FAT login failed for team #{@environment.team_id}."
      rescue ::Selenium::WebDriver::Error::WebDriverError
        raise AuthenticationError, "FAT login page was not usable for team #{@environment.team_id}."
      end

      private

      def fill(id:, value:)
        field = @driver.find_element(id: id)
        field.clear
        field.send_keys(value)
      end

      def dismiss_cookie_banner
        button = @driver.find_elements(xpath: "//button[normalize-space()='Essential only']").first
        button&.click
      rescue ::Selenium::WebDriver::Error::WebDriverError
        nil
      end
    end
  end
end
