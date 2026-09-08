# frozen_string_literal: true

require "test_helper"

class InsurancePreference::InsuranceComparatorTest < ActiveSupport::TestCase
  test "regression: substring, parenthetical, merge, and typo cases" do
    required = [
      "INNOVAGE (PACE)",
      "MEDICAID VIRGINIA",
      "EMERGENCY MEDICAID VIRGINIA",
      "MEDICAID VIRGINIA PENDING",
      "GOVT EMP HOSPITAL ASSC.",
      "UNITED HEALTHCARE CHOICE PLUS",
      "HIGHMARK BLUE CROSS PENNSYLVANIA"
    ]
    actual = [
      "INNOVAGE",
      "EMERGENCY MEDICAID VIRGINIA",
      "MEDICAID VIRGINIA PENDING",
      "GOVT EMP HOSPITAL ASSC. UNITED HEALTHCARE CHOICE PLUS",
      "HIGHMARK BLUE CROSS PENNSYLVANI"
    ]

    result = InsurancePreference::InsuranceComparator.new(required, actual).call

    assert_equal ["MEDICAID VIRGINIA"], result.missing
    assert_equal [], result.extras

    kinds = result.variants.map { |v| [v.required, v.kind] }
    assert_includes kinds, ["INNOVAGE (PACE)", "parenthetical"]
    assert_includes kinds, ["GOVT EMP HOSPITAL ASSC.", "delimiter_merge_sheet"]
    assert_includes kinds, ["UNITED HEALTHCARE CHOICE PLUS", "delimiter_merge_sheet"]
    assert_includes kinds, ["HIGHMARK BLUE CROSS PENNSYLVANIA", "typo"]
    refute result.required_status["MEDICAID VIRGINIA"].present
    assert result.required_status["EMERGENCY MEDICAID VIRGINIA"].present
  end

  test "master-side delimiter merge treats two actual entries as one required plan" do
    required = ["GOVT EMP HOSPITAL ASSC. UNITED HEALTHCARE CHOICE PLUS"]
    actual = ["GOVT EMP HOSPITAL ASSC.", "UNITED HEALTHCARE CHOICE PLUS"]

    result = InsurancePreference::InsuranceComparator.new(required, actual).call

    assert_equal [], result.missing
    assert_equal [], result.extras
    assert_equal "delimiter_merge_master", result.required_status[required.first].kind
  end
end
