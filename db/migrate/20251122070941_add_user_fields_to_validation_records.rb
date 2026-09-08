class AddUserFieldsToValidationRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :validation_records, :user_id, :integer
    add_column :validation_records, :user_email, :string
  end
end
