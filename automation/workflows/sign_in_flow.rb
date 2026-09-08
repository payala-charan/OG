# automation/workflows/sign_in_flow.rb
require_relative '../pages/home_page'
require_relative '../pages/login_page'
require_relative '../pages/features_page'

module Workflows
  class SignInFlow
    def run
      home_page = Pages::HomePage.new
      login_page = Pages::LoginPage.new
      features_page = Pages::FeaturesPage.new

      # 1) Homepage open, click sign-in
      home_page.visit_home
      home_page.go_to_sign_in

      # 2) Sign-in page action using credentials
      login_page.login('payalacharan@gmail.com', '1234567')
      # login_page.login(ENV['EMAIL'], ENV['PASSWORD'])

      # 3) Verify we are at features/index page
      unless features_page.loaded?
        raise "❌ Login flow failed. Expected features index not loaded (#{current_url})"
      end

      features_page.print_status
      puts "🚀 Login workflow finished successfully."
    end
  end
end
