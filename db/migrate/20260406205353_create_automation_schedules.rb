class CreateAutomationSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :automation_schedules do |t|
      t.string :frequency
      t.string :time_of_day
      t.datetime :next_run_at
      t.boolean :active
      t.integer :user_id

      t.timestamps
    end
  end
end
