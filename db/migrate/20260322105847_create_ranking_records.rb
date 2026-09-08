class CreateRankingRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ranking_records do |t|
      t.json :data
      t.integer :user_id
      t.string :user_email

      t.timestamps
    end
    add_index :ranking_records, :user_id
  end
end
