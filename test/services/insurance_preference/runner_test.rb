# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "axlsx"

class InsurancePreference::RunnerTest < ActiveSupport::TestCase
  test "runner completes a code-only validation and attaches output" do
    master = build_master
    biosimilar = build_biosimilar
    run = InsurancePreferenceValidationRun.create!(
      user: users(:one),
      model_validation_enabled: false,
      master_file_name: "master.xlsx",
      biosimilar_file_name: "bio.xlsx",
      status: :pending
    )
    run.master_file.attach(io: File.open(master.path), filename: "master.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    run.biosimilar_file.attach(io: File.open(biosimilar.path), filename: "bio.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    InsurancePreference::Runner.new(run).call
    run.reload

    assert run.complete?
    assert run.output_file.attached?
    assert run.validation_rows.any?
    assert_equal "FAIL_MISSING", run.validation_rows.first.validation_status
  ensure
    master&.close!
    biosimilar&.close!
  end

  test "mock model validation records agreement category" do
    run = InsurancePreferenceValidationRun.create!(user: users(:one), status: :complete)
    row = run.validation_rows.create!(
      generic_name: "Bevacizumab (Avastin)",
      validation_status: "FAIL_MISSING",
      missing_insurances: ["MEDICAID VIRGINIA"].to_json,
      extra_insurances: [].to_json,
      claude_insurances_json: [{ "text" => "MEDICAID VIRGINIA", "color" => "red" }]
    )

    result = InsurancePreference::ModelValidator.new(row, provider: "mock").call
    assert_equal "FAIL", result[:model_validation_status]
    assert result[:agrees_with_code]
  end

  private

  def build_master
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "BEVACIZUMAB") do |sheet|
      sheet.add_row ["Insurance - Medicare/Commercial/VA only", "Avastin J9035", "Hyperlink"]
      sheet.add_row ["AETNA PPO", "Y"]
      sheet.add_row ["MEDICAID VIRGINIA", "Y"]
    end
    file = Tempfile.new(["master", ".xlsx"])
    package.serialize(file.path)
    file
  end

  def build_biosimilar
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Sheet1") do |sheet|
      sheet.add_row ["GENERIC NAME", "GENERIC NAME GROUP", "INSURANCES"]
      sheet.add_row ["Bevacizumab (Avastin) 100mg", "BEVACIZUMAB", "AETNA PPO"]
    end
    file = Tempfile.new(["bio", ".xlsx"])
    package.serialize(file.path)
    file
  end
end
