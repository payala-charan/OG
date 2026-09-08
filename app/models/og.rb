class Og < ApplicationRecord
  def self.ransackable_attributes(auth_object = nil)
    %w[
      id generic_name brand strength ndc_code reimbursement_per_billing_unit
      billing_unit_per_package_size cms_reimbursement_per_package
      cost_three_forty_b cms_margin_three_forty_b_cost gpo_cost
      accounting_period_id reimbursement_id generic_name_group
      created_at updated_at cms_percent_margin match
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
