class Insurance < ApplicationRecord
  belongs_to :payor
  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id name payor_id created_at updated_at]
  end

  # Allow only safe associations to be searchable
  def self.ransackable_associations(auth_object = nil)
    %w[payor]
  end
end
