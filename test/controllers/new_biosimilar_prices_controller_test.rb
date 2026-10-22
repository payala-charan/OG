require "test_helper"

class NewBiosimilarPricesControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.create!(
      email: "biosimilar-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
    @temp_files = []
  end

  teardown do
    Array(@temp_files).each { |file| file.close! }
  end

  test "imports every tab and stores the tab name as category" do
    log_in
    workbook = pricing_workbook

    assert_difference -> { NewBiosimilarPrice.count }, 2 do
      post new_biosimilar_prices_path, params: { file: Rack::Test::UploadedFile.new(workbook.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    end

    assert_redirected_to new_biosimilar_prices_path
    follow_redirect!
    assert_match "Imported 2 rows from 2 sheets", response.body

    uhc = NewBiosimilarPrice.find_by!(category: "UHC", ndc_code: "00069031501")
    assert_equal "Bevacizumab-BVZR (Zirabev) 100mg/4ml Injection", uhc.generic_name
    assert_equal "1", uhc.match
    assert_equal "00069031501", uhc.ndc_code
    assert_nil uhc.alternate_ndc_code
    assert_equal "Q5118", uhc.hcpcs_code
    assert_equal "10", uhc.billing_unit
    assert_in_delta 25.889, uhc.cms_reimbursement_per_billing_unit
    assert_equal 10, uhc.billing_unit_per_package_size
    assert_in_delta 258.89, uhc.cms_reimbursement_per_package
    assert_equal "UMR UHC", uhc.insurances
    assert_in_delta 38.4056, uhc.payrate_reimbursement_per_billing_unit
    assert_in_delta 384.056, uhc.payrate_reimbursement_per_package
    assert_in_delta 136.95, uhc.cost_three_forty_b
    assert_in_delta 3.565886225, uhc.cost_per_unit_three_forty_b
    assert_in_delta 9.376960073, uhc.blended_cost_three_forty_b
    assert_in_delta 247.106, uhc.cms_margin_three_forty_b_cost
    assert_in_delta 6.434113775, uhc.cms_margin_per_unit_three_forty_b_cost
    assert_in_delta 16.91933622, uhc.blended_cms_margin_three_forty_b_cost
    assert_in_delta 1.804351953, uhc.cms_percent_margin
    assert_in_delta 1.804351953, uhc.blended_cms_percent_margin
    assert_in_delta 453.07, uhc.gpo_cost
    assert_in_delta 11.79697752, uhc.cost_per_unit_gpo
    assert_in_delta 31.02182308, uhc.blended_gpo_cost
    assert_in_delta(-69.014, uhc.cms_margin_gpo_cost)
    assert_in_delta(-1.796977524, uhc.cms_margin_per_unit_gpo)
    assert_in_delta(-4.725526781, uhc.blended_cms_margin_gpo_cost)
    assert_in_delta(-0.1523252478, uhc.gpo_percent_margin)
    assert_in_delta(-0.1523291126, uhc.blended_gpo_percent_margin)
    assert_equal 7, uhc.accounting_period_id
    assert_equal 7, uhc.reimbursement_id
    assert_equal "BEVACIZUMAB", uhc.generic_name_group
    assert_equal "non_preferred_conversion", uhc.status
    assert_equal "209", uhc.team_id

    cms = NewBiosimilarPrice.find_by!(category: "CMS")
    assert_equal "Bevacizumab-AWWB (Mvasi) 100mg/4ml Injection", cms.generic_name
    assert_equal "55513020601", cms.ndc_code
    assert_equal "55513020621", cms.alternate_ndc_code
    assert_equal "GENERIC AETNA", cms.insurances
    assert_equal "1mg", cms.billing_unit
    assert_nil cms.status
  end

  private

  def log_in
    post login_path, params: { email: @user.email, password: "password123" }
  end

  def pricing_workbook
    headers = [
      "GENERIC NAME", "MATCH", "NDC CODE", "ALTERNATE NDC CODE", "OTHER NDC CODES",
      "HCPCS CODE", "BILLING UNIT", "CMS REIMBURSEMENT PER BILLING UNIT",
      "BILLING UNIT PER PACKAGE SIZE", "CMS REIMBURSEMENT PER PACKAGE", "INSURANCES",
      "PAYRATE REIMBURSEMENT PER BILLING UNIT", "PAYRATE  REIMBURSEMENT PER PACKAGE",
      "COST THREE FORTY B", "COST PER UNIT THREE FORTY B", "BLENDED 340B COST",
      "CMS MARGIN 340B COST", "CMS MARGIN PER UNIT THREE FORTY B COST", "BLENDED 340B MARGIN",
      "CMS PERCENT MARGIN", "BLENDED PERCENT MARGIN", "GPO COST", "COST PER UNIT GPO",
      "BLENDED GPO COST", "CMS MARGIN GPO COST", "CMS MARGIN PER UNIT GPO",
      "BLENDED GPO MARGIN", "GPO PERCENT MARGIN", "BLENDED GPO PERCENT MARGIN",
      "ACCOUNTING PERIOD ID", "REIMBURSEMENT ID", "GENERIC NAME GROUP", "STATUS", "TEAM ID"
    ]
    uhc_row = [
      "Bevacizumab-BVZR (Zirabev) 100mg/4ml Injection", "1", "00069031501", nil, nil,
      "Q5118", 10, 25.889, 10, 258.89, "UMR UHC",
      38.4056, 384.056, 136.95, 3.565886225, 9.376960073,
      247.106, 6.434113775, 16.91933622, 1.804351953, 1.804351953,
      453.07, 11.79697752, 31.02182308, -69.014, -1.796977524,
      -4.725526781, -0.1523252478, -0.1523291126, 7, 7,
      "BEVACIZUMAB", "non_preferred_conversion", "209"
    ]
    cms_headers = headers.dup
    cms_headers[0] = "l"
    cms_row = uhc_row.dup
    cms_row[0] = "Bevacizumab-AWWB (Mvasi) 100mg/4ml Injection"
    cms_row[2] = "55513020601"
    cms_row[3] = "55513020621"
    cms_row[6] = "1mg"
    cms_row[10] = "\nGENERIC AETNA"
    cms_row[32] = nil

    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "UHC") do |sheet|
      sheet.add_row headers
      sheet.add_row uhc_row, types: row_types(uhc_row)
      sheet.add_row Array.new(headers.length)
    end
    package.workbook.add_worksheet(name: "CMS") do |sheet|
      sheet.add_row cms_headers
      sheet.add_row cms_row, types: row_types(cms_row)
    end

    file = Tempfile.new([ "pricing", ".xlsx" ])
    @temp_files << file
    package.serialize(file.path)
    file
  end

  def row_types(row)
    row.map { |value| value.is_a?(String) ? :string : nil }
  end
end
