class BrandInsuranceMapping < ApplicationRecord
  belongs_to :user, optional: true

  validates :file_name, presence: true

  def parsed_mappings
    mappings.is_a?(Hash) ? mappings : (JSON.parse(mappings.to_s) rescue {})
  end
end
