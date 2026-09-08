class AddBlendedColumnsToOg < ActiveRecord::Migration[8.0]
  def change
    add_column :ogs, :blended_cost_340B, :float
    add_column :ogs, :blended_cms_margin_340B, :float
    add_column :ogs, :blended_cms_340B_percent_margin, :float
    add_column :ogs, :blended_cost_gpo, :float
    add_column :ogs, :blended_cms_margin_gpo, :float
    add_column :ogs, :blended_gpo_percent_margin, :float
  end
end
