class CreateKetteringInsurances < ActiveRecord::Migration[8.0]
  def change
    create_table :kettering_insurances do |t|
      t.string :generic_name_group
      t.string :brand_name
      t.string :primary_payor_name
      t.string :benefit_plan_name
      t.string :hcpcs_code
      t.decimal :pay_rate, precision: 15, scale: 4
      t.decimal :price, precision: 15, scale: 4

      t.timestamps
    end
  end
end