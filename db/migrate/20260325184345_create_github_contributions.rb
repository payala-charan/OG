class CreateGithubContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :github_contributions do |t|
      t.string :author
      t.datetime :date
      t.integer :commits
      t.references :github_repository, null: false, foreign_key: true

      t.timestamps
    end
  end
end
