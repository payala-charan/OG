class CreateNameMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :name_matches do |t|
      t.string :name
      t.integer :corresponding_value

      t.timestamps
    end
  end
end
