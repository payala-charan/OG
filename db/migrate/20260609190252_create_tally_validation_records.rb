class CreateTallyValidationRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :tally_validation_records do |t|
      t.json :data
      t.integer :user_id
      t.string :user_email
      t.string :individual_file_name
      t.string :grouped_file_name

      t.timestamps
    end
  end
end
