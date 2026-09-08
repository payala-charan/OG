class CreateAutoValidateRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :auto_validate_records do |t|
      t.json :data
      t.integer :user_id
      t.string :user_email
      t.timestamps
    end
  end
end
