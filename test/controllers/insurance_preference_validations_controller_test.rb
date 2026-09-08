# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "axlsx"

class InsurancePreferenceValidationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ip_#{SecureRandom.hex(4)}@example.com", password: "password")
    post login_path, params: { email: @user.email, password: "password" }
    @files = []
  end

  teardown do
    @files.each { |file| file.close! rescue nil }
  end

  test "unauthenticated users are sent to login" do
    delete logout_path
    get insurance_preference_validations_path
    assert_redirected_to login_path
  end

  test "create runs validation and download works" do
    master = uploaded_xlsx("master") do |wb|
      wb.add_worksheet(name: "BEVACIZUMAB") do |sheet|
        sheet.add_row ["Insurance - Medicare/Commercial/VA only", "Avastin J9035", "Hyperlink"]
        sheet.add_row ["AETNA PPO", "Y"]
      end
    end
    biosimilar = uploaded_xlsx("bio") do |wb|
      wb.add_worksheet(name: "Sheet1") do |sheet|
        sheet.add_row ["GENERIC NAME", "GENERIC NAME GROUP", "INSURANCES"]
        sheet.add_row ["Bevacizumab (Avastin) 100mg", "BEVACIZUMAB", "AETNA PPO"]
      end
    end

    assert_difference -> { InsurancePreferenceValidationRun.count }, 1 do
      post insurance_preference_validations_path, params: {
        master_file: master,
        biosimilar_file: biosimilar,
        model_validation_enabled: "0"
      }
    end

    run = InsurancePreferenceValidationRun.order(:id).last
    assert_redirected_to insurance_preference_validation_path(run)
    InsurancePreferenceValidationJob.perform_now(run.id)
    run.reload
    assert run.complete?

    get insurance_preference_validation_path(run, format: :json)
    assert_response :success
    assert_equal "complete", JSON.parse(@response.body)["status"]

    get download_insurance_preference_validation_path(run)
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", @response.media_type
  end

  private

  def uploaded_xlsx(name)
    package = Axlsx::Package.new
    yield package.workbook
    file = Tempfile.new([name, ".xlsx"])
    @files << file
    package.serialize(file.path)
    Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end
end
