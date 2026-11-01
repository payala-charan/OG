# frozen_string_literal: true

class TransferFatTablesRun19 < ActiveRecord::Migration[8.0]
  def change
    create_table :invoice_conversions do |t|
      t.integer "utilization_report_id"
      t.string "conversion_product"
      t.integer "conversion_percentage"
      t.float "conversion_product_cost_per_unit"
      t.float "conversion_product_total_cost"
      t.float "conversion_product_total_insurance_payment"
      t.float "conversion_product_total_margin"
      t.float "conversion_product_percent_margin"
      t.float "blended_conversion_cost_per_unit"
      t.float "blended_conversion_total_margin"
      t.float "blended_conversion_percent_margin"
      t.float "blended_conversion_cost_difference"
      t.float "blended_conversion_margin_difference"
      t.float "blended_conversion_percent_margin_difference"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "user_id"
      t.string "team_id"
      t.string "converted_to"
      t.string "status", default: "individual", null: false
      t.string "conversion_type"
      t.string "percentage_basis", default: "", null: false
      t.index ["status"], name: "index_invoice_conversions_on_status"
      t.index ["team_id"], name: "index_invoice_conversions_on_team_id"
      t.index ["user_id", "team_id", "conversion_type"], name: "index_invoice_conversions_user_team_percentage", where: "((conversion_type)::text = 'percentage'::text)"
      t.index ["user_id"], name: "index_invoice_conversions_on_user_id"
      t.index ["utilization_report_id", "status", "conversion_type"], name: "index_invoice_conversions_system_status_type", unique: true, where: "((user_id IS NULL) AND (conversion_type IS NOT NULL))"
      t.index ["utilization_report_id", "status"], name: "index_invoice_conversions_legacy_system_status", unique: true, where: "((user_id IS NULL) AND (conversion_type IS NULL))"
      t.index ["utilization_report_id", "user_id", "status", "conversion_type", "percentage_basis"], name: "index_invoice_conversions_user_status_type", unique: true, where: "((user_id IS NOT NULL) AND (conversion_type IS NOT NULL))"
      t.index ["utilization_report_id", "user_id", "status"], name: "index_invoice_conversions_legacy_user_status", unique: true, where: "((user_id IS NOT NULL) AND (conversion_type IS NULL))"
    end
  end
end
