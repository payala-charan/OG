class CreateNdcResults < ActiveRecord::Migration[8.0]
  def change
    create_table :ndc_results do |t|
      t.string :ndc_code
      t.float :result_value

      t.timestamps
    end
  end
end
