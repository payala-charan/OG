class CreateBiosimilarPrices < ActiveRecord::Migration[8.0]
  def change
    create_table :biosimilar_prices do |t|
      t.string  :generic_name
      t.string  :hcpcs_code
      t.string  :billing_unit
      t.decimal :reimbursement_per_billing_unit, precision: 15, scale: 4
      t.decimal :billing_unit_per_package_size, precision: 15, scale: 4
      t.decimal :gpo_cost, precision: 15, scale: 4
      t.decimal :cost_three_forty_b, precision: 15, scale: 4
      t.string  :extracted_brand_name
      t.decimal :cms_reimbursement_per_package, precision: 15, scale: 4
      t.decimal :cms_margin_gpo_cost, precision: 15, scale: 4
      t.decimal :cms_margin_three_forty_b_cost, precision: 15, scale: 4
      t.string  :generic_name_group
      t.string  :extracted_strength
      t.decimal :best_margin, precision: 15, scale: 4
      t.string  :insurances
      t.decimal :utilization_best_margin, precision: 15, scale: 4
      t.string  :reimbursement
      t.string  :ndc_code
      t.string  :status
      t.string  :alternate_ndc_code
      t.string  :other_ndc_codes
      t.integer :reimbursement_id
      t.integer :accounting_period_id
      t.decimal :cost_per_unit_three_forty_b, precision: 15, scale: 4
      t.decimal :cms_percent_margin, precision: 10, scale: 4
      t.decimal :gpo_percent_margin, precision: 10, scale: 4
      t.decimal :blended_cost_three_forty_b, precision: 15, scale: 4
      t.decimal :blended_gpo_cost, precision: 15, scale: 4
      t.decimal :blended_cms_margin_three_forty_b_cost, precision: 15, scale: 4
      t.decimal :blended_cms_percent_margin, precision: 10, scale: 4
      t.decimal :blended_cms_margin_gpo_cost, precision: 15, scale: 4
      t.decimal :blended_gpo_percent_margin, precision: 10, scale: 4
      t.string  :ranked_by
      t.string  :match

      t.timestamps
    end
  end
end
