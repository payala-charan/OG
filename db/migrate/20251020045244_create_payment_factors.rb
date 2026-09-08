class CreatePaymentFactors < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_factors do |t|
      t.string :payor
      t.integer :factor

      t.timestamps
    end
  end
end
