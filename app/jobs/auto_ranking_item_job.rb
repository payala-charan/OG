class AutoRankingItemJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = AutomationBatchItem.find_by(id: item_id)
    return unless item
    
    batch = item.automation_batch
    
    begin
      item.update(status: 'running')
      
      # Call the exhaustive service natively
      result = AutoRankingService.new(
        user_id: 10130,
        team_id: item.team_id,
        generic_name_group: item.generic_name_group,
        quarter: item.quarter
      ).call
      
      record = result.is_a?(Hash) ? result[:record] : nil
      mismatches_count = record&.data&.fetch('debug_mismatches', [])&.length.to_i
      
      if mismatches_count > 0
        error_str = "Ranking logic mismatch: #{mismatches_count} errors found"
        item.update!(status: 'failed', error_message: error_str)
        AutomationBatch.transaction do
          batch.lock!
          batch.failed_jobs += 1
          batch.save!
        end
      else
        item.update!(status: 'completed', error_message: nil)
        AutomationBatch.transaction do
          batch.lock!
          batch.completed_jobs += 1
          batch.save!
        end
      end
    rescue => e
      item.update!(status: 'failed', error_message: e.message[0..500])
      
      AutomationBatch.transaction do
        batch.lock!
        batch.failed_jobs += 1
        batch.save!
      end
    end
    
    # Check if batch is entirely done natively
    batch.check_completion_and_notify!
  end
end
