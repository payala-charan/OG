class CreateAutoRankingRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :auto_ranking_records do |t|
      t.json :data
      t.integer :user_id
      t.string :user_email

      t.timestamps
    end
  end
end
