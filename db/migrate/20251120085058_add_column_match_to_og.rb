class AddColumnMatchToOg < ActiveRecord::Migration[8.0]
  def change
    add_column :ogs, :match, :integer
  end
end
