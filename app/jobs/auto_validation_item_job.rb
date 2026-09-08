class AutoValidationItemJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = AutomationBatchItem.find_by(id: item_id)
    return unless item
    
    batch = item.automation_batch
    
    begin
      item.update(status: 'running')
      
      # Call the exhaustive service natively
      result = AutoValidationService.new(
        user_id: 10130,
        team_id: item.team_id,
        generic_name_group: item.generic_name_group,
        quarter: item.quarter,
        conversion_criteria: "highest_margin"
      ).call
      
      mismatches_count = 0
      if result.is_a?(Hash) && result[:validated_data].present?
        result[:validated_data].each do |row|
          row.each do |k, v|
            if v.is_a?(Hash) && v.key?(:match) && [false, "false"].include?(v[:match].to_s.downcase)
              mismatches_count += 1
            end
          end
        end
      end
      
      if mismatches_count > 0
        error_str = "Validation logic mismatch: #{mismatches_count} errors found"
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
