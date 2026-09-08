# automation/workflows/conversion_upload_flow.rb
require_relative '../pages/conversions_upload_page'
require_relative '../pages/features_page'
require_relative '../pages/login_page'
require_relative '../pages/home_page'

module Workflows
  class ConversionUploadFlow
    def run
      # 1) Sign in first (if needed)
      home_page = Pages::HomePage.new
      login_page = Pages::LoginPage.new
      features_page = Pages::FeaturesPage.new

      home_page.visit_home
      home_page.go_to_sign_in
      login_page.login('payalacharan@gmail.com', '1234567')

      unless features_page.loaded?
        raise "❌ Could not load features page after login"
      end

      features_page.print_status

      # 2) Upload conversion file on validations page
      upload_page = Pages::ConversionUploadPage.new
      automation_root = File.dirname(__dir__) # if __dir__ is automation/workflows
      file_path = File.join(automation_root, 'files', 'St.Charles Q4 2025 Bevacizumab main.xlsx')

      upload_page.upload_file(file_path)

      puts "🚀 Conversion upload workflow finished successfully."
    end
  end
end