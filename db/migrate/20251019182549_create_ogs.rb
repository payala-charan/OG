class CreateOgs < ActiveRecord::Migration[8.0]
  def change
    create_table :ogs do |t|
      t.string :generic_name
      t.string :brand
      t.string :strength
      t.string :ndc_code
      t.float :reimbursement_per_billing_unit
      t.integer :billing_unit_per_package_size
      t.float :cms_reimbursement_per_package
      t.float :cost_three_forty_b
      t.float :cms_margin_three_forty_b_cost
      t.float :gpo_cost
      t.integer :accounting_period_id
      t.integer :reimbursement_id
      t.string :generic_name_group

      t.timestamps
    end
  end
end
