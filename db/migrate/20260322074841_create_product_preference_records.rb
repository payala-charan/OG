class CreateProductPreferenceRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :product_preference_records do |t|
      t.jsonb :data, default: {}
      t.integer :user_id
      t.string :user_email

      t.timestamps
    end

    add_index :product_preference_records, :user_id
    add_index :product_preference_records, :data, using: :gin
  end
end
