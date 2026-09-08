# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "axlsx"

class InsurancePreference::ValidatorWorkbookTest < ActiveSupport::TestCase
  setup do
    @temp_files = []
  end

  teardown do
    @temp_files.each do |file|
      file.close!
    rescue StandardError
      FileUtils.rm_f(file.path) if file.respond_to?(:path)
    end
  end

  test "parses multi-tab biosimilar files with inferred groups and New Insurances priority" do
    master = write_xlsx do |wb|
      wb.add_worksheet(name: "BEVACIZUMAB") do |sheet|
        sheet.add_row ["Insurance - Medicare/Commercial/VA only", "Avastin J9035", "Zirabev Q5118", "Hyperlink"]
        sheet.add_row ["AETNA PPO", "Y", "N"]
        sheet.add_row ["MEDICAID VIRGINIA", "N", "Y"]
        sheet.add_row []
        sheet.add_row ["Insurance - Medicaid Plans Only", "Zirabev Q5118", "Avastin J9035", "Hyperlink"]
        sheet.add_row ["UNITED HEALTHCARE CHOICE PLUS", "Y", "N"]
      end
      wb.add_worksheet(name: "HYALURONATE SODIUM") do |sheet|
        sheet.add_row ["Insurance - Medicare/Commercial/VA only", "Synvisc J7325", "Hyperlink"]
        sheet.add_row ["AETNA PPO", "Y"]
      end
    end

    biosimilar = write_xlsx do |wb|
      wb.add_worksheet(name: "Sheet1") do |sheet|
        sheet.add_row ["GENERIC NAME", "GENERIC NAME GROUP", "INSURANCES", "HCPCS CODE", "COST", "MARGIN"]
        sheet.add_row ["Bevacizumab-BVZR (Zirabev) 100mg/4ml Injection", "BEVACIZUMAB", "AETNA PPO, MEDICAID VIRGINIA", "Q5118", 10, "=E2*2"]
        sheet.add_row ["Sodium Hyaluronate (Genvisc 850) 25mg", "SODIUM HYALURONATE", "AETNA PPO", "J7326", 5, "=E3*2"]
      end
      wb.add_worksheet(name: "Hari") do |sheet|
        sheet.add_row ["GENERIC NAME", "NEW INSURANCES", "INSURANCES", "STATUS"]
        sheet.add_row ["Bevacizumab (Avastin) 100mg/4ml Injection", "AETNA PPO", "SHOULD NOT USE", "not_alternative"]
      end
      wb.add_worksheet(name: "Charan") do |sheet|
        sheet.add_row ["GENERIC NAME", "INSURANCES"]
        sheet.add_row ["Bevacizumab-BVZR (Zirabev) 400mg/16ml Injection", "UNITED HEALTHCARE CHOICE PLUS"]
      end
    end

    result = InsurancePreference::Validator.new(master_path: master.path, biosimilar_path: biosimilar.path).call
    rows = result.rows.index_by { |row| [row.source_sheet_name, row.generic_name] }

    zirabev = rows[["Sheet1", "Bevacizumab-BVZR (Zirabev) 100mg/4ml Injection"]]
    assert_equal "OK", zirabev.match_method
    assert_match(/Zirabev/i, zirabev.matched_brand_column)
    assert_includes zirabev.missing_insurances, "UNITED HEALTHCARE CHOICE PLUS"
    assert_equal "FAIL_MISSING", zirabev.validation_status
    refute_empty zirabev.claude_insurances

    genvisc = rows[["Sheet1", "Sodium Hyaluronate (Genvisc 850) 25mg"]]
    assert_equal "NO_MATCH", genvisc.match_method
    assert_equal "NO_MASTER_MAPPING", genvisc.validation_status
    assert_empty genvisc.claude_insurances

    avastin = rows[["Hari", "Bevacizumab (Avastin) 100mg/4ml Injection"]]
    assert_equal "New Insurances", avastin.source_column_used
    assert_equal "PASS", avastin.validation_status

    inferred = rows[["Charan", "Bevacizumab-BVZR (Zirabev) 400mg/16ml Injection"]]
    assert inferred.generic_name_group_inferred
    assert_equal "BEVACIZUMAB", inferred.generic_name_group
    assert result.warnings.any? { |warning| warning.include?("Charan") && warning.include?("inferred") }

    output = tempfile("out", ".xlsx")
    InsurancePreference::WorkbookAnnotator.new(
      biosimilar.path,
      { column_name: "Claude Insurances", sheets: result.sheet_annotations }
    ).call(output.path)

    require "rubyXL"
    book = RubyXL::Parser.parse(output.path)
    sheet1 = book["Sheet1"]
    header = sheet1[0].cells.map { |cell| cell&.value }
    assert_includes header, "Claude Insurances"
    ins_idx = header.index("INSURANCES")
    claude_idx = header.index("Claude Insurances")
    assert_equal ins_idx + 1, claude_idx

    margin = sheet1[1][header.index("MARGIN")]
    expected_formula = InsurancePreference::FormulaShifter.shift_formula("E2*2", claude_idx + 1)
    actual_formula = margin.formula.respond_to?(:expression) ? margin.formula.expression : margin.formula.to_s
    assert_equal "F2*2", expected_formula
    assert_equal expected_formula, actual_formula
    assert_nil sheet1[2][claude_idx]&.value || (sheet1[2][claude_idx]&.is && rich_text_of(sheet1[2][claude_idx]))
    genvisc_cell = sheet1[2][claude_idx]
    assert blank_rich_or_nil?(genvisc_cell), "NO_MASTER_MAPPING rows must leave Claude Insurances blank"
  end

  test "formula shifter bumps columns at or after the insert point" do
    assert_equal "K2*L2", InsurancePreference::FormulaShifter.shift_formula("J2*K2", 10)
    assert_equal "$K2/$L2", InsurancePreference::FormulaShifter.shift_formula("$J2/$K2", 10)
    assert_equal "A2+B2", InsurancePreference::FormulaShifter.shift_formula("A2+B2", 10)
  end

  private

  def write_xlsx
    package = Axlsx::Package.new
    yield package.workbook
    file = tempfile("wb", ".xlsx")
    package.serialize(file.path)
    file
  end

  def tempfile(prefix, ext)
    file = Tempfile.new([prefix, ext])
    @temp_files << file
    file
  end

  def rich_text_of(cell)
    return unless cell&.is.respond_to?(:r)

    Array(cell.is.r).map { |run| run.t&.value }.join
  end

  def blank_rich_or_nil?(cell)
    return true if cell.nil? || cell.value.nil? || cell.value.to_s.strip.empty?

    text = rich_text_of(cell)
    text.nil? || text.strip.empty?
  end
end
