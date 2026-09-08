# frozen_string_literal: true

class CreateInsurancePreferenceValidations < ActiveRecord::Migration[8.0]
  def change
    create_table :insurance_preference_validation_runs do |t|
      t.references :user, foreign_key: true
      t.integer :status, null: false, default: 0
      t.boolean :model_validation_enabled, null: false, default: false
      t.string :claude_column_name, default: "Claude Insurances"
      t.string :master_file_name
      t.string :biosimilar_file_name
      t.text :error_message
      t.string :progress_message
      t.jsonb :warnings, default: []
      t.jsonb :summary, default: {}
      t.datetime :finished_at
      t.timestamps
    end

    create_table :insurance_preference_validation_rows do |t|
      t.references :insurance_preference_validation_run, null: false, foreign_key: true, index: { name: "idx_ip_validation_rows_on_run_id" }
      t.string :source_sheet_name
      t.integer :source_row_number
      t.string :generic_name
      t.string :generic_name_group
      t.boolean :generic_name_group_inferred, default: false
      t.string :hcpcs_code
      t.string :status_flag
      t.string :master_tab
      t.string :matched_brand_column
      t.float :match_confidence
      t.string :match_method
      t.string :source_column_used
      t.integer :required_count
      t.integer :actual_count
      t.string :validation_status
      t.text :missing_insurances
      t.text :spelling_mismatches
      t.text :extra_insurances
      t.jsonb :claude_insurances_json, default: []
      t.text :notes
      t.timestamps
    end

    create_table :insurance_preference_model_results do |t|
      t.references :insurance_preference_validation_row, null: false, foreign_key: true, index: { name: "idx_ip_model_results_on_row_id" }
      t.string :model_name
      t.boolean :agrees_with_code
      t.string :model_validation_status
      t.text :model_missing_insurances
      t.text :model_notes
      t.jsonb :raw_response, default: {}
      t.timestamps
    end

    add_index :insurance_preference_validation_rows, :validation_status, name: "idx_ip_validation_rows_on_status"
    add_index :insurance_preference_validation_rows, :source_sheet_name, name: "idx_ip_validation_rows_on_sheet"
  end
end
