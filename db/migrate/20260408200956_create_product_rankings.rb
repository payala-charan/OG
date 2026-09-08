class CreateProductRankings < ActiveRecord::Migration[8.0]
  def change
    create_table :product_rankings do |t|
      t.string :generic_name_group
      t.string :team_id
      t.integer :accounting_period_id
      t.string :payor
      t.json :insurances
      t.json :results
      t.json :rankings

      t.timestamps
    end
  end
end
