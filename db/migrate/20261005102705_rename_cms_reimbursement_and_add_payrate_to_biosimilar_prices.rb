class RenameCmsReimbursementAndAddPayrateToBiosimilarPrices < ActiveRecord::Migration[8.0]
  def change
    rename_column :new_biosimilar_prices, :reimbursement_per_billing_unit, :cms_reimbursement_per_billing_unit
    add_column :new_biosimilar_prices, :payrate_reimbursement_per_billing_unit, :float
    add_column :new_biosimilar_prices, :payrate_reimbursement_per_package, :float
    add_column :new_biosimilar_prices, :category, :string
    add_column :new_biosimilar_prices, :cms_margin_per_unit_three_forty_b_cost, :float
    add_column :new_biosimilar_prices, :cost_per_unit_gpo, :float
    add_column :new_biosimilar_prices, :cms_margin_per_unit_gpo, :float
    remove_column :new_biosimilar_prices, :extracted_insurances
  end
end
