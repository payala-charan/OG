class ChangeDatTypeInFactor < ActiveRecord::Migration[8.0]
  def change
    change_column :payment_factors, :factor, :float
  end
end
