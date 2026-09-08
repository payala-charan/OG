class CreateGithubAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :github_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :username
      t.string :access_token

      t.timestamps
    end
  end
end
