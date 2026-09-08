class User < ApplicationRecord
  has_secure_password
  has_many :validation_records, dependent: :destroy
  has_many :tally_validation_records, dependent: :destroy
  has_many :insurance_preference_validation_runs, dependent: :destroy
  validates :email, presence: true, uniqueness: true
  validates :password, presence: true, length: { minimum: 6 }, if: :password
  has_one :github_account, dependent: :destroy
  has_one :gmail_connection, dependent: :destroy
  has_many :gmail_extractions, dependent: :destroy
end
