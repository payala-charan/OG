class CreateDatabaseTransferRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :database_transfer_runs do |t|
      t.bigint :user_id
      t.integer :status, default: 0, null: false
      t.boolean :rehearsal, default: false, null: false
      t.string :source_database, null: false
      t.string :target_database, null: false
      t.jsonb :selected_tables, default: [], null: false
      t.jsonb :planned_tables, default: [], null: false
      t.string :plan_fingerprint, null: false
      t.string :progress_message
      t.text :error_message
      t.jsonb :summary, default: {}, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :database_transfer_runs, :user_id
    add_index :database_transfer_runs, :status
  end
end
