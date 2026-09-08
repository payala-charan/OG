require_relative 'config/environment'
require 'csv'

puts "Testing validation logic by mocking a sheet row..."
controller = RankingRecordsController.new

# Mock DB Data
db_insurances = ["bendamustine", "treanda", "bendeka", "belrapzo", "vivimusta"]

headers = ["Generic Name", "PACIFICSOURCE MEDICARE ADVANTAGE", "BCBS MED ADV 1ST OR PREF CHOICE"]
row_data = {
  "Bendamustine (Belrapzo) 100mg/4ml" => [2, "X"],
  "Bendamustine (Bendeka) 100mg/4ml" => [3, "X"],
  "Bendamustine (Treanda) 100mg/4ml" => [7, "X"],
  "Bendamustine 100mg/4ml" => [4, "X"]
}

row_data.each do |generic_name, values|
  puts "Validating #{generic_name}..."
  
  # For PacificSource:
  should_rank_pacific = controller.send(:should_have_numeric_rank?, db_insurances, generic_name)
  has_rank_pacific = controller.send(:actual_has_numeric_rank?, values[0])
  status_pacific = (should_rank_pacific && has_rank_pacific) || (!should_rank_pacific && !has_rank_pacific) ? "success" : "failure"
  
  puts "  PacificSource [expected: #{should_rank_pacific ? 'rank' : 'X'}, actual: #{values[0]}] -> #{status_pacific}"
  
  # For BCBS:
  should_rank_bcbs = controller.send(:should_have_numeric_rank?, [], generic_name)
  has_rank_bcbs = controller.send(:actual_has_numeric_rank?, values[1])
  status_bcbs = (should_rank_bcbs && has_rank_bcbs) || (!should_rank_bcbs && !has_rank_bcbs) ? "success" : "failure"
  
  puts "  BCBS          [expected: #{should_rank_bcbs ? 'rank' : 'X'}, actual: #{values[1]}] -> #{status_bcbs}"
end
