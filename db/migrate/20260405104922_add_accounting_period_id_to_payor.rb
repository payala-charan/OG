class AddAccountingPeriodIdToPayor < ActiveRecord::Migration[8.0]
  def change
    add_column :payors, :accounting_period_id, :integer
  end
end
