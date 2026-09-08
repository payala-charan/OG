class AddTeamIdToScreenAnalysis < ActiveRecord::Migration[8.0]
  def change
    add_column :screen_analyses, :team_id, :integer
  end
end
