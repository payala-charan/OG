class GithubRepository < ApplicationRecord
  belongs_to :github_account
  has_many :github_pull_requests, dependent: :destroy
  has_many :github_contributions, dependent: :destroy
end
