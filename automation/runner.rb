# automation/runner.rb
require_relative 'config'
require_relative 'workflows/features_overview_flow'

include Capybara::DSL

workflow = Workflows::FeaturesOverviewFlow.new
workflow.run

puts "🚀 Automation Completed!"

unless ENV['WEB_TRIGGER'] == 'true'
  puts "🛑 Press ENTER to close browser..."
  gets
end