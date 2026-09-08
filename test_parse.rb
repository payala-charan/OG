require_relative 'config/environment'

puts "Testing parse_insurance_names..."
controller = RankingRecordsController.new
puts controller.send(:parse_insurance_names, "[\"bendamustine\", \"treanda\", \"bendeka\", \"belrapzo\", \"vivimusta\"]").inspect

puts "Testing parens_brand_token..."
puts controller.send(:parens_brand_token, "Bendamustine (Belrapzo) 100mg/4ml").inspect
puts controller.send(:parens_brand_token, "Bendamustine 100mg/4ml").inspect

puts "Testing extract_generic_group..."
puts controller.send(:extract_generic_group, "Bendamustine (Belrapzo) 100mg/4ml").inspect
puts controller.send(:extract_generic_group, "Bendamustine 100mg/4ml").inspect
