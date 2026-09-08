class CreateNdcCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :ndc_codes do |t|
      t.string :code

      t.timestamps
    end
  end
end
