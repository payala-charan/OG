class AddcolumntoOg < ActiveRecord::Migration[8.0]
  def change
    add_column :ogs, :cms_percent_margin, :float
  end
end
