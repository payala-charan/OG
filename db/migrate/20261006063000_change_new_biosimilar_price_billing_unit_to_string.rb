class ChangeNewBiosimilarPriceBillingUnitToString < ActiveRecord::Migration[8.0]
  def up
    change_column :new_biosimilar_prices, :billing_unit, :string, using: "billing_unit::text"
  end

  def down
    change_column :new_biosimilar_prices, :billing_unit, :float,
      using: "CASE WHEN billing_unit ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN billing_unit::double precision ELSE NULL END"
  end
end