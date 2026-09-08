class CreateUploadedFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :uploaded_files do |t|
      t.string :file_name
      t.string :quarter
      t.string :category

      t.timestamps
    end
  end
end
