class AddTeamIdToPayors < ActiveRecord::Migration[8.0]
  def change
    add_column :payors, :team_id, :integer
    add_index :payors, :team_id
  end
end
