class SystemSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    AutomationSchedule.where(active: true).where("next_run_at <= ?", Time.current).each do |schedule|
      # Trigger Batch
      batch = schedule.automation_batches.create!(
        status: 'pending',
        batch_type: schedule.schedule_type,
        total_jobs: 100, completed_jobs: 0, failed_jobs: 0,
        user_id: schedule.user_id
      )
      
      BatchDispatcherJob.perform_later(batch.id)

      # Update next_run_at based on frequency and time_of_day
      time = Time.parse(schedule.time_of_day) rescue Time.current.beginning_of_day
      
      base_date = Date.current
      base_date = base_date + 1.day if Time.current > Time.current.change(hour: time.hour, min: time.min)

      next_run = case schedule.frequency.downcase
                 when 'daily' then base_date + 1.day
                 when 'weekly' then base_date + 1.week
                 when 'monthly' then base_date + 1.month
                 else base_date + 1.day
                 end
                 
      schedule.update(next_run_at: next_run.change(hour: time.hour, min: time.min))
    end
  end
end
