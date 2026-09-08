class CreateSchemaData < ActiveRecord::Migration[8.0]
  def change
    create_table :schema_data do |t|
      t.text :content

      t.timestamps
    end
  end
end
