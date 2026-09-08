class DeletionOfTables < ActiveRecord::Migration[8.0]
  def change
    drop_table :insurances, if_exists: true
    drop_table :payors, if_exists: true
  end
end
