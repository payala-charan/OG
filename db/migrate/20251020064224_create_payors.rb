class CreatePayors < ActiveRecord::Migration[8.0]
  def change
    create_table :payors do |t|
      t.string :name
      t.string :generic_name

      t.timestamps
    end
  end
end
