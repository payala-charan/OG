class Payor < ApplicationRecord
  has_many :insurances, dependent: :destroy

  validates :name, presence: true
  validates :generic_name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id name generic_name created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[insurances]
  end
end

