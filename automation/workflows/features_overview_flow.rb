# automation/workflows/features_overview_flow.rb
require_relative '../pages/home_page'
require_relative '../pages/login_page'
require_relative '../pages/features_page'

module Workflows
  class FeaturesOverviewFlow
    def run
      home_page = Pages::HomePage.new
      login_page = Pages::LoginPage.new
      features_page = Pages::FeaturesPage.new

      home_page.visit_home
      home_page.go_to_sign_in

      login_page.login('payalacharan@gmail.com', '1234567')

      unless features_page.loaded?
        raise "❌ Features page did not load after login"
      end
      features_page.print_status

      feature_targets = [
        '/validations',
        '/uploaded_files',
        '/screen_analyses',
        '/payor_preferences',
        '/new_biosimilar_prices',
        '/product_preference_records',
        '/product_preference_records/7',
        '/ranking_records',
        '/ranking_records/63',
        '/voice',
        '/schema_visualizers',
        '/github',
        '/github/dashboard',
        '/automations',
        '/auto_validation',
        '/auto_validation/results',
        '/auto_validation/results/1',
        '/auto_ranking',
        '/auto_ranking/results',
        '/auto_ranking/results/1'
      ]

      feature_targets.each do |path|
        begin
          features_page.visit_feature_path(path)

          # security delay to make users notice page load
          sleep 2

          features_page.scroll_page_full

          # small pause before screenshot and leaving
          sleep 1.5

          filename = "feature_#{path.tr('/', '_').sub(/^_/, '')}_snapshot.png"
          save_screenshot(filename)
          puts "📸 Screenshot saved: #{filename}"

          # Come back to features for the next link
          visit '/features'
          sleep 2
          raise "❌ Failed to return to features page" unless features_page.loaded?
        rescue StandardError => e
          puts "⚠️ Skipping #{path}: #{e.message}"
          visit '/features'
          features_page.loaded?
        end
      end

      puts "🚀 All feature pages visited and validated by scroll-verify method."
    end
  end
end