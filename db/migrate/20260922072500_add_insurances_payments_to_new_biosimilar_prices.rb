class AddInsurancesPaymentsToNewBiosimilarPrices < ActiveRecord::Migration[8.0]
  def change
    add_column :new_biosimilar_prices, :insurances_payments, :jsonb, default: {}
  end
end
