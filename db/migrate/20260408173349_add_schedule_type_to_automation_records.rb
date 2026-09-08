class AddScheduleTypeToAutomationRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :automation_schedules, :schedule_type, :string, default: 'utilization'
    add_column :automation_batches, :batch_type, :string, default: 'utilization'
  end
end
