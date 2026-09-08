class CreateValidationRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :validation_records do |t|
      t.json :data

      t.timestamps
    end
  end
end
