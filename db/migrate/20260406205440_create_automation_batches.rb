class CreateAutomationBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :automation_batches do |t|
      t.references :automation_schedule, null: false, foreign_key: true
      t.string :status
      t.integer :total_jobs
      t.integer :completed_jobs
      t.integer :failed_jobs
      t.integer :user_id

      t.timestamps
    end
  end
end
