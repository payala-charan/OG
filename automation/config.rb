# automation/config.rb
require 'capybara'
require 'capybara/dsl'
# Capybara.default_max_wait_time = 10

# Capybara.register_driver :selenium_chrome do |app|
#   options = Selenium::WebDriver::Chrome::Options.new
#   options.add_argument("--start-maximized")

#   Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
# end

Capybara.default_driver = :selenium_chrome
Capybara.app_host = ENV.fetch('APP_HOST', 'http://localhost:1234')

module Automation
  def self.setup
    include Capybara::DSL
  end
end