class CreatePayorPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :payor_preferences do |t|
      t.integer :accounting_period_id
      t.string :generic_name_group
      t.string :payor
      t.text :insurances
      t.integer :strength
      t.string :conversion_type
      t.string :conversion_target_col
      t.string :factor
      t.json :values
      t.string :result

      t.timestamps
    end
  end
end
