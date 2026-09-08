class AddTeamIdToPayorPreferences < ActiveRecord::Migration[8.0]
  def change
    add_column :payor_preferences, :team_id, :integer
    add_index :payor_preferences, :team_id
  end
end
