class CreateExcelRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :excel_records do |t|
      t.jsonb :data

      t.timestamps
    end
  end
end
