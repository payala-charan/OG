class CreateBrandInsuranceMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :brand_insurance_mappings do |t|
      t.json :mappings, default: {}
      t.integer :user_id
      t.string :user_email
      t.string :file_name

      t.timestamps
    end
  end
end
