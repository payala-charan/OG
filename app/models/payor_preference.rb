class PayorPreference < ApplicationRecord
  def self.ransackable_attributes(auth_object = nil)
    %w[
      id accounting_period_id generic_name_group payor insurances strength
      conversion_type conversion_target_col factor values result
      created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
