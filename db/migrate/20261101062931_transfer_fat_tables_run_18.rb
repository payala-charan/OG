# frozen_string_literal: true

class TransferFatTablesRun18 < ActiveRecord::Migration[8.0]
  def change
    create_table :utilization_reports do |t|
      t.string "ordering_mode"
      t.string "medication_id"
      t.integer "order_line"
      t.string "administered_quantity"
      t.string "administered_qty_unit"
      t.string "hcpcs_code"
      t.string "financial_class"
      t.string "administration_department"
      t.string "hospital_name"
      t.string "generic_name_group"
      t.string "cms_payment_per_unit"
      t.string "price_without_cost_dist_minus"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "har"
      t.string "csn"
      t.string "mrn"
      t.integer "patient_age"
      t.string "description"
      t.string "display_name"
      t.datetime "administration_instant"
      t.string "principal_dx"
      t.string "diagnosis_two"
      t.string "diagnosis_three"
      t.string "diagnosis_four"
      t.string "prescribing_provider_nm"
      t.string "order_department"
      t.string "dispense_department"
      t.string "hospital_group"
      t.string "extracted_brand_name"
      t.string "health_system"
      t.string "mar_action"
      t.string "qty_unit_name"
      t.string "pack_desc"
      t.string "charge_type"
      t.string "charge_class"
      t.string "primary_dx"
      t.string "quantity"
      t.float "cms_asp"
      t.float "insurance_payment_per_dose"
      t.float "total_margin"
      t.float "percent_margin"
      t.string "data_month"
      t.string "reimbursement"
      t.string "quarter"
      t.float "charge"
      t.string "admin_amount"
      t.string "admin_unit"
      t.float "total_units"
      t.float "actual_reimbursement"
      t.float "units"
      t.string "category"
      t.integer "accounting_period_id"
      t.bigint "reimbursement_id"
      t.string "team_id"
      t.float "cost_per_unit_three_forty_b"
      t.float "cms_total_units"
      t.string "converted_to"
      t.float "actual_price"
      t.float "reimbursement_per_package"
      t.string "insurance_class"
      t.index ["extracted_brand_name"], name: "index_utilization_reports_on_extracted_brand_name"
      t.index ["generic_name_group"], name: "index_utilization_reports_on_generic_name_group"
      t.index ["hospital_name", "generic_name_group"], name: "idx_inv_on_hosp_gen_grp"
      t.index ["hospital_name"], name: "index_utilization_reports_on_hospital_name"
      t.index ["reimbursement_id"], name: "index_utilization_reports_on_reimbursement_id"
      t.index ["team_id", "accounting_period_id", "category", "generic_name_group"], name: "idx_util_reports_team_period_category_group"
      t.index ["team_id", "generic_name_group", "category"], name: "idx_util_reports_team_group_category"
      t.index ["team_id", "hospital_name"], name: "idx_util_reports_team_hospital_uncategorized", where: "(category IS NULL)"
      t.index ["team_id"], name: "index_utilization_reports_on_team_id"
    end

    create_table :ndc_codes do |t|
      t.bigint "utilization_report_id", null: false
      t.string "ndc_code", null: false
      t.string "strength"
      t.string "package_size"
      t.string "package_description"
      t.string "brand_name"
      t.string "generic_name"
      t.string "package_unit"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["ndc_code"], name: "index_ndc_codes_on_ndc_code"
      t.index ["utilization_report_id"], name: "index_ndc_codes_on_utilization_report_id"
    end

    create_table :primary_payors do |t|
      t.bigint "utilization_report_id", null: false
      t.string "primary_payor_name", null: false
      t.string "benefit_plan_name"
      t.float "insurance_factor"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["benefit_plan_name"], name: "index_primary_payors_on_benefit_plan_name"
      t.index ["primary_payor_name"], name: "index_primary_payors_on_primary_payor_name"
      t.index ["utilization_report_id"], name: "index_primary_payors_on_utilization_report_id"
    end

    create_table "test_invoice_conversions", id: :serial, force: :cascade do |t|
      t.integer "utilization_report_id", null: false
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
      t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
      t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
      t.string "source_brand_name"
      t.string "source_generic_name"
  
      t.unique_constraint ["utilization_report_id"], name: "test_invoice_conversions_utilization_report_id_key"
    end

    create_table :utilization_orders do |t|
      t.bigint "utilization_report_id", null: false
      t.datetime "order_date_time", precision: nil
      t.string "order_status"
      t.string "order_id"
      t.string "order_name"
      t.text "order_description"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["order_id"], name: "index_utilization_orders_on_order_id"
      t.index ["utilization_report_id"], name: "index_utilization_orders_on_utilization_report_id"
    end

    add_foreign_key :ndc_codes, :utilization_reports

    add_foreign_key :primary_payors, :utilization_reports

    add_foreign_key :test_invoice_conversions, :utilization_reports, name: :test_invoice_conversions_utilization_report_id_fkey, on_delete: :cascade

    add_foreign_key :utilization_orders, :utilization_reports
  end
end
