class CreateInsuranceFactors < ActiveRecord::Migration[7.0]
  def change
    create_table :insurance_factors do |t|
      t.string :primary_payor_name
      t.string :benefit_plan_name
      t.string :category

      t.float  :rate_percent
      t.float  :insurance_factor

      t.string :team_id

      t.timestamps
    end
  end
end