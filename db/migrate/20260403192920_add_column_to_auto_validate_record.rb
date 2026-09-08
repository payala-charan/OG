class AddColumnToAutoValidateRecord < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_validate_records, :file, :string
  end
end
