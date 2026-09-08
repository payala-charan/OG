# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_25_143000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_admin_comments", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "alert_emails", force: :cascade do |t|
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "auto_ranking_records", force: :cascade do |t|
    t.json "data"
    t.integer "user_id"
    t.string "user_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file"
  end

  create_table "auto_validate_records", force: :cascade do |t|
    t.json "data"
    t.integer "user_id"
    t.string "user_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file"
  end

  create_table "automation_batch_items", force: :cascade do |t|
    t.bigint "automation_batch_id", null: false
    t.string "generic_name_group"
    t.string "team_id"
    t.string "quarter"
    t.string "status"
    t.text "error_message"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["automation_batch_id"], name: "index_automation_batch_items_on_automation_batch_id"
  end

  create_table "automation_batches", force: :cascade do |t|
    t.bigint "automation_schedule_id", null: false
    t.string "status"
    t.integer "total_jobs"
    t.integer "completed_jobs"
    t.integer "failed_jobs"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "batch_type", default: "utilization"
    t.index ["automation_schedule_id"], name: "index_automation_batches_on_automation_schedule_id"
  end

  create_table "automation_schedules", force: :cascade do |t|
    t.string "frequency"
    t.string "time_of_day"
    t.datetime "next_run_at"
    t.boolean "active"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "schedule_type", default: "utilization"
  end

  create_table "biosimilar_prices", force: :cascade do |t|
    t.string "generic_name"
    t.string "hcpcs_code"
    t.string "billing_unit"
    t.float "reimbursement_per_billing_unit"
    t.float "billing_unit_per_package_size"
    t.float "gpo_cost"
    t.float "cost_three_forty_b"
    t.string "extracted_brand_name"
    t.float "cms_reimbursement_per_package"
    t.float "cms_margin_gpo_cost"
    t.float "cms_margin_three_forty_b_cost"
    t.string "generic_name_group"
    t.string "extracted_strength"
    t.float "best_margin"
    t.string "insurances"
    t.float "utilization_best_margin"
    t.string "reimbursement"
    t.string "ndc_code"
    t.string "status"
    t.string "alternate_ndc_code"
    t.string "other_ndc_codes"
    t.integer "reimbursement_id"
    t.integer "accounting_period_id"
    t.float "cost_per_unit_three_forty_b"
    t.float "cms_percent_margin"
    t.float "gpo_percent_margin"
    t.float "blended_cost_three_forty_b"
    t.float "blended_gpo_cost"
    t.float "blended_cms_margin_three_forty_b_cost"
    t.float "blended_cms_percent_margin"
    t.float "blended_cms_margin_gpo_cost"
    t.float "blended_gpo_percent_margin"
    t.string "ranked_by"
    t.string "match"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "brand_insurance_mappings", force: :cascade do |t|
    t.json "mappings", default: {}
    t.integer "user_id"
    t.string "user_email"
    t.string "file_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "excel_records", force: :cascade do |t|
    t.jsonb "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_name"
    t.index ["file_name"], name: "index_excel_records_on_file_name"
  end

  create_table "github_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "username"
    t.string "access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_github_accounts_on_user_id"
  end

  create_table "github_contributions", force: :cascade do |t|
    t.string "author"
    t.datetime "date"
    t.integer "commits"
    t.bigint "github_repository_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_repository_id"], name: "index_github_contributions_on_github_repository_id"
  end

  create_table "github_pull_requests", force: :cascade do |t|
    t.string "repository"
    t.integer "pr_number"
    t.string "title"
    t.string "author"
    t.string "state"
    t.boolean "merged"
    t.string "merged_by"
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.bigint "github_repository_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_repository_id"], name: "index_github_pull_requests_on_github_repository_id"
  end

  create_table "github_repositories", force: :cascade do |t|
    t.string "name"
    t.string "owner"
    t.bigint "github_account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_account_id"], name: "index_github_repositories_on_github_account_id"
  end

  create_table "gmail_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "access_token"
    t.text "refresh_token"
    t.string "google_email", default: "", null: false
    t.datetime "token_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_gmail_connections_on_user_id", unique: true
  end

  create_table "gmail_extracted_emails", force: :cascade do |t|
    t.bigint "gmail_extraction_id", null: false
    t.string "gmail_message_id", null: false
    t.string "subject", default: "", null: false
    t.text "body_text"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gmail_extraction_id", "gmail_message_id"], name: "index_gmail_extracted_emails_on_extraction_and_gmail_id", unique: true
    t.index ["gmail_extraction_id"], name: "index_gmail_extracted_emails_on_gmail_extraction_id"
  end

  create_table "gmail_extractions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "gmail_connection_id", null: false
    t.string "recipient_email", null: false
    t.date "start_on", null: false
    t.date "end_on", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.integer "total_fetched", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gmail_connection_id"], name: "index_gmail_extractions_on_gmail_connection_id"
    t.index ["user_id"], name: "index_gmail_extractions_on_user_id"
  end

  create_table "insurance_factors", force: :cascade do |t|
    t.string "primary_payor_name"
    t.string "benefit_plan_name"
    t.string "category"
    t.float "rate_percent"
    t.float "insurance_factor"
    t.string "team_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "insurance_preference_model_results", force: :cascade do |t|
    t.bigint "insurance_preference_validation_row_id", null: false
    t.string "model_name"
    t.boolean "agrees_with_code"
    t.string "model_validation_status"
    t.text "model_missing_insurances"
    t.text "model_notes"
    t.jsonb "raw_response", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["insurance_preference_validation_row_id"], name: "idx_ip_model_results_on_row_id"
  end

  create_table "insurance_preference_validation_rows", force: :cascade do |t|
    t.bigint "insurance_preference_validation_run_id", null: false
    t.string "source_sheet_name"
    t.integer "source_row_number"
    t.string "generic_name"
    t.string "generic_name_group"
    t.boolean "generic_name_group_inferred", default: false
    t.string "hcpcs_code"
    t.string "status_flag"
    t.string "master_tab"
    t.string "matched_brand_column"
    t.float "match_confidence"
    t.string "match_method"
    t.string "source_column_used"
    t.integer "required_count"
    t.integer "actual_count"
    t.string "validation_status"
    t.text "missing_insurances"
    t.text "spelling_mismatches"
    t.text "extra_insurances"
    t.jsonb "claude_insurances_json", default: []
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["insurance_preference_validation_run_id"], name: "idx_ip_validation_rows_on_run_id"
    t.index ["source_sheet_name"], name: "idx_ip_validation_rows_on_sheet"
    t.index ["validation_status"], name: "idx_ip_validation_rows_on_status"
  end

  create_table "insurance_preference_validation_runs", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "status", default: 0, null: false
    t.boolean "model_validation_enabled", default: false, null: false
    t.string "claude_column_name", default: "Claude Insurances"
    t.string "master_file_name"
    t.string "biosimilar_file_name"
    t.text "error_message"
    t.string "progress_message"
    t.jsonb "warnings", default: []
    t.jsonb "summary", default: {}
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_insurance_preference_validation_runs_on_user_id"
  end

  create_table "insurances", force: :cascade do |t|
    t.string "name"
    t.bigint "payor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_insurances_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["payor_id"], name: "index_insurances_on_payor_id"
  end

  create_table "name_matches", force: :cascade do |t|
    t.string "name"
    t.integer "corresponding_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_name_matches_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "ndc_codes", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_name"
    t.index ["file_name", "code"], name: "index_ndc_codes_on_file_name_and_code"
  end

  create_table "ndc_results", force: :cascade do |t|
    t.string "ndc_code"
    t.float "result_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_name"
    t.index ["file_name"], name: "index_ndc_results_on_file_name"
  end

  create_table "new_biosimilar_prices", force: :cascade do |t|
    t.string "generic_name"
    t.string "hcpcs_code"
    t.float "billing_unit"
    t.float "reimbursement_per_billing_unit"
    t.integer "billing_unit_per_package_size"
    t.float "gpo_cost"
    t.float "cost_three_forty_b"
    t.string "extracted_brand_name"
    t.float "cms_reimbursement_per_package"
    t.float "cms_margin_gpo_cost"
    t.float "cms_margin_three_forty_b_cost"
    t.string "generic_name_group"
    t.string "extracted_strength"
    t.boolean "best_margin"
    t.string "insurances"
    t.boolean "utilization_best_margin"
    t.string "reimbursement"
    t.string "ndc_code"
    t.string "status"
    t.string "alternate_ndc_code"
    t.string "other_ndc_codes"
    t.integer "reimbursement_id"
    t.integer "accounting_period_id"
    t.float "cost_per_unit_three_forty_b"
    t.float "cms_percent_margin"
    t.float "gpo_percent_margin"
    t.float "blended_cost_three_forty_b"
    t.float "blended_gpo_cost"
    t.float "blended_cms_margin_three_forty_b_cost"
    t.float "blended_cms_percent_margin"
    t.float "blended_cms_margin_gpo_cost"
    t.float "blended_gpo_percent_margin"
    t.string "ranked_by"
    t.string "match"
    t.string "team_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "extracted_insurances", default: [], array: true
  end

  create_table "ogs", force: :cascade do |t|
    t.string "generic_name"
    t.string "brand"
    t.string "strength"
    t.string "ndc_code"
    t.float "reimbursement_per_billing_unit"
    t.integer "billing_unit_per_package_size"
    t.float "cms_reimbursement_per_package"
    t.float "cost_three_forty_b"
    t.float "cms_margin_three_forty_b_cost"
    t.float "gpo_cost"
    t.integer "accounting_period_id"
    t.integer "reimbursement_id"
    t.string "generic_name_group"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "cms_percent_margin"
    t.integer "match"
    t.float "blended_cost_340B"
    t.float "blended_cms_margin_340B"
    t.float "blended_cms_340B_percent_margin"
    t.float "blended_cost_gpo"
    t.float "blended_cms_margin_gpo"
    t.float "blended_gpo_percent_margin"
    t.index ["brand"], name: "index_ogs_on_brand_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["generic_name"], name: "index_ogs_on_generic_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["generic_name_group"], name: "index_ogs_on_generic_name_group_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["ndc_code"], name: "index_ogs_on_ndc_code_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["strength"], name: "index_ogs_on_strength_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "payment_factors", force: :cascade do |t|
    t.string "payor"
    t.float "factor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payor"], name: "index_payment_factors_on_payor_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "payor_preferences", force: :cascade do |t|
    t.integer "accounting_period_id"
    t.string "generic_name_group"
    t.string "payor"
    t.text "insurances"
    t.integer "strength"
    t.string "conversion_type"
    t.string "conversion_target_col"
    t.string "factor"
    t.json "values"
    t.string "result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "team_id"
    t.index ["conversion_target_col"], name: "index_payor_preferences_on_conversion_target_col_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversion_type"], name: "index_payor_preferences_on_conversion_type_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["factor"], name: "index_payor_preferences_on_factor_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["generic_name_group"], name: "index_payor_preferences_on_generic_name_group_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["insurances"], name: "index_payor_preferences_on_insurances_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["payor"], name: "index_payor_preferences_on_payor_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["result"], name: "index_payor_preferences_on_result_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["team_id"], name: "index_payor_preferences_on_team_id"
  end

  create_table "payors", force: :cascade do |t|
    t.string "name"
    t.string "generic_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "team_id"
    t.integer "accounting_period_id"
    t.index ["generic_name"], name: "index_payors_on_generic_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["name"], name: "index_payors_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["team_id"], name: "index_payors_on_team_id"
  end

  create_table "product_preference_records", force: :cascade do |t|
    t.jsonb "data", default: {}
    t.integer "user_id"
    t.string "user_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_product_preference_records_on_data", using: :gin
    t.index ["user_id"], name: "index_product_preference_records_on_user_id"
  end

  create_table "product_rankings", force: :cascade do |t|
    t.string "generic_name_group"
    t.string "team_id"
    t.integer "accounting_period_id"
    t.string "payor"
    t.json "insurances"
    t.json "results"
    t.json "rankings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ranking_records", force: :cascade do |t|
    t.json "data"
    t.integer "user_id"
    t.string "user_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_ranking_records_on_user_id"
  end

  create_table "samples", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_samples_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "schema_data", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "screen_analyses", force: :cascade do |t|
    t.string "title", null: false
    t.text "summary", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "team_id"
  end

  create_table "students", force: :cascade do |t|
    t.string "name"
    t.string "branch"
    t.integer "rollno"
    t.float "cgpa"
    t.string "college"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch"], name: "index_students_on_branch_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["college"], name: "index_students_on_college_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["name"], name: "index_students_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "tally_validation_records", force: :cascade do |t|
    t.json "data"
    t.integer "user_id"
    t.string "user_email"
    t.string "individual_file_name"
    t.string "grouped_file_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "uploaded_files", force: :cascade do |t|
    t.string "file_name"
    t.string "quarter"
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_uploaded_files_on_category_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["file_name"], name: "index_uploaded_files_on_file_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["quarter"], name: "index_uploaded_files_on_quarter_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["password_digest"], name: "index_users_on_password_digest_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "validation_records", force: :cascade do |t|
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "user_email"
  end

  create_table "voice_query_logs", force: :cascade do |t|
    t.text "query"
    t.text "response"
    t.string "result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "automation_batch_items", "automation_batches"
  add_foreign_key "automation_batches", "automation_schedules"
  add_foreign_key "github_accounts", "users"
  add_foreign_key "github_contributions", "github_repositories"
  add_foreign_key "github_pull_requests", "github_repositories"
  add_foreign_key "github_repositories", "github_accounts"
  add_foreign_key "gmail_connections", "users"
  add_foreign_key "gmail_extracted_emails", "gmail_extractions"
  add_foreign_key "gmail_extractions", "gmail_connections"
  add_foreign_key "gmail_extractions", "users"
  add_foreign_key "insurance_preference_model_results", "insurance_preference_validation_rows"
  add_foreign_key "insurance_preference_validation_rows", "insurance_preference_validation_runs"
  add_foreign_key "insurance_preference_validation_runs", "users"
  add_foreign_key "insurances", "payors"
end
