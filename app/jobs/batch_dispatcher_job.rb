class BatchDispatcherJob < ApplicationJob
  queue_as :default

  VALID_GROUPS = ["Bendamustine", "Bevacizumab", "Filgrastim", "Infliximab", 
                  "Pegfilgrastim", "Rituximab", "Trastuzumab", "Tocilizumab", 
                  "Leuprolide Acetate", "Denosumab"].freeze
  VALID_TEAMS = ["198", "209"].freeze
  VALID_QUARTERS = ["1", "2", "3", "4", "5"].freeze

  def perform(batch_id)
    batch = AutomationBatch.find(batch_id)
    batch.update(status: 'running')

    delay_counter = 0

    VALID_GROUPS.each do |group|
      VALID_TEAMS.each do |team|
        VALID_QUARTERS.each do |quarter|
          
          item = batch.automation_batch_items.create!(
            generic_name_group: group,
            team_id: team,
            quarter: quarter,
            status: 'pending',
            user_id: batch.user_id
          )
          
          # Wait approx 60 seconds linearly to avoid spamming the request natively
          if batch.batch_type == 'ranking'
            AutoRankingItemJob.set(wait: (delay_counter * 60).seconds).perform_later(item.id)
          else
            AutoValidationItemJob.set(wait: (delay_counter * 60).seconds).perform_later(item.id)
          end
          delay_counter += 1

        end
      end
    end
  end
end
