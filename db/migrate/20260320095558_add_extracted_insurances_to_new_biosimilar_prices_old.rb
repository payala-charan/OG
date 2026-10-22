class AddExtractedInsurancesToNewBiosimilarPrices < ActiveRecord::Migration[8.0]
  def change
     add_column :new_biosimilar_prices, :extracted_insurances, :string, array: true, default: []
  end
end
