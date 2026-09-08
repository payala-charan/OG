class AddFileToAutoRankingRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_ranking_records, :file, :string
  end
end
