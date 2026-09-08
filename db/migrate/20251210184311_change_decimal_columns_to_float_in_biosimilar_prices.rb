class ChangeDecimalColumnsToFloatInBiosimilarPrices < ActiveRecord::Migration[7.0]
  def change
    change_column :biosimilar_prices, :reimbursement_per_billing_unit, :float
    change_column :biosimilar_prices, :billing_unit_per_package_size, :float
    change_column :biosimilar_prices, :gpo_cost, :float
    change_column :biosimilar_prices, :cost_three_forty_b, :float
    change_column :biosimilar_prices, :cms_reimbursement_per_package, :float
    change_column :biosimilar_prices, :cms_margin_gpo_cost, :float
    change_column :biosimilar_prices, :cms_margin_three_forty_b_cost, :float
    change_column :biosimilar_prices, :cost_per_unit_three_forty_b, :float
    change_column :biosimilar_prices, :cms_percent_margin, :float
    change_column :biosimilar_prices, :gpo_percent_margin, :float
    change_column :biosimilar_prices, :blended_cost_three_forty_b, :float
    change_column :biosimilar_prices, :blended_gpo_cost, :float
    change_column :biosimilar_prices, :blended_cms_margin_three_forty_b_cost, :float
    change_column :biosimilar_prices, :blended_cms_percent_margin, :float
    change_column :biosimilar_prices, :blended_cms_margin_gpo_cost, :float
    change_column :biosimilar_prices, :blended_gpo_percent_margin, :float
    change_column :biosimilar_prices, :best_margin, :float
    change_column :biosimilar_prices, :utilization_best_margin, :float
  end
end
