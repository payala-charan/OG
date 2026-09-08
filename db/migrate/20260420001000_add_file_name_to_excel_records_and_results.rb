class AddFileNameToExcelRecordsAndResults < ActiveRecord::Migration[8.0]
  def change
    add_column :excel_records, :file_name, :string
    add_column :ndc_codes, :file_name, :string
    add_column :ndc_results, :file_name, :string

    add_index :excel_records, :file_name
    add_index :ndc_codes, [:file_name, :code]
    add_index :ndc_results, :file_name
  end
end
