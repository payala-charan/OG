# frozen_string_literal: true

class CreateFatValidations < ActiveRecord::Migration[8.0]
  def change
    create_table :fat_validation_runs do |t|
      t.references :user, foreign_key: true
      t.string :team_id, null: false
      t.string :environment, null: false
      t.string :report_type, null: false
      t.string :data_source, null: false
      t.integer :accounting_period_id
      t.integer :status, null: false, default: 0
      t.integer :total_records, null: false, default: 0
      t.integer :passed_records, null: false, default: 0
      t.integer :failed_records, null: false, default: 0
      t.text :error_message
      t.string :progress_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :fat_validation_runs,
              [ :team_id, :environment, :report_type, :status, :completed_at ],
              name: "index_fat_validation_runs_on_latest"

    create_table :fat_validation_results do |t|
      t.references :fat_validation_run, null: false, foreign_key: true
      t.string :generic_group
      t.string :column_name, null: false
      t.decimal :expected_value, precision: 16, scale: 2
      t.decimal :actual_value, precision: 16, scale: 2
      t.decimal :difference, precision: 16, scale: 2
      t.string :status, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end

    add_index :fat_validation_results, [ :fat_validation_run_id, :status ],
              name: "index_fat_validation_results_on_run_and_status"
    add_index :fat_validation_results, [ :fat_validation_run_id, :generic_group ],
              name: "index_fat_validation_results_on_run_and_group"
  end
end
