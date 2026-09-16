class KetteringInsurance < ApplicationRecord
  validates :generic_name_group, :brand_name, :primary_payor_name,
            :benefit_plan_name, presence: true
end