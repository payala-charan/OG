class CreateGithubRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :github_repositories do |t|
      t.string :name
      t.string :owner
      t.references :github_account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
