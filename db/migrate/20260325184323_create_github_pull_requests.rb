class CreateGithubPullRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :github_pull_requests do |t|
      t.string :repository
      t.integer :pr_number
      t.string :title
      t.string :author
      t.string :state
      t.boolean :merged
      t.string :merged_by
      t.datetime :opened_at
      t.datetime :closed_at
      t.references :github_repository, null: false, foreign_key: true

      t.timestamps
    end
  end
end
