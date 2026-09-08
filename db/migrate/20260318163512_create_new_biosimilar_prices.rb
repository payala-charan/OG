class CreateNewBiosimilarPrices < ActiveRecord::Migration[8.0]
  def change
    create_table :new_biosimilar_prices do |t|
      t.string  :generic_name
      t.string  :hcpcs_code
      t.float   :billing_unit
      t.float   :reimbursement_per_billing_unit
      t.integer :billing_unit_per_package_size
      t.float   :gpo_cost
      t.float   :cost_three_forty_b

      t.string  :extracted_brand_name
      t.float   :cms_reimbursement_per_package
      t.float   :cms_margin_gpo_cost
      t.float   :cms_margin_three_forty_b_cost

      t.string  :generic_name_group
      t.string  :extracted_strength

      t.boolean :best_margin
      t.string  :insurances
      t.boolean :utilization_best_margin

      t.string  :reimbursement
      t.string  :ndc_code
      t.string  :status

      t.string  :alternate_ndc_code
      t.string  :other_ndc_codes

      t.integer :reimbursement_id
      t.integer :accounting_period_id

      t.float   :cost_per_unit_three_forty_b
      t.float   :cms_percent_margin
      t.float   :gpo_percent_margin

      t.float   :blended_cost_three_forty_b
      t.float   :blended_gpo_cost
      t.float   :blended_cms_margin_three_forty_b_cost
      t.float   :blended_cms_percent_margin
      t.float   :blended_cms_margin_gpo_cost
      t.float   :blended_gpo_percent_margin

      t.string  :ranked_by
      t.string  :match
      t.string  :team_id

      t.timestamps
    end
  end
end