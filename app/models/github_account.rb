class GithubAccount < ApplicationRecord
  belongs_to :user
 has_many :github_repositories, dependent: :destroy
end
