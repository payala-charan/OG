class CreateAutomationBatchItems < ActiveRecord::Migration[8.0]
  def change
    create_table :automation_batch_items do |t|
      t.references :automation_batch, null: false, foreign_key: true
      t.string :generic_name_group
      t.string :team_id
      t.string :quarter
      t.string :status
      t.text :error_message
      t.integer :user_id

      t.timestamps
    end
  end
end
