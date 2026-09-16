class ChangeKetteringInsurancePayRateToString < ActiveRecord::Migration[8.0]
  def up
    change_column :kettering_insurances, :pay_rate, :string
  end

  def down
    change_column :kettering_insurances, :pay_rate, :decimal, precision: 15, scale: 4
  end
end