class ProductPreferenceValidatorService

  def initialize(row)
    @row = row
  end

  def call
    {
      "CMS REIMBURSEMENT PER PACKAGE" => validate_cms_reimbursement,
      "COST PER UNIT 340B" => validate_cost_per_unit_340b,
      "CMS MARGIN 340B COST" => validate_margin_340b,
      "CMS PERCENT MARGIN" => validate_percent_margin_340b,
      "CMS MARGIN GPO COST" => validate_margin_gpo,
      "GPO PERCENT MARGIN" => validate_percent_margin_gpo,
      "BLENDED CMS PERCENT MARGIN" => validate_blended_percent_340b,
      "BLENDED GPO PERCENT MARGIN" => validate_blended_percent_gpo
    }.compact
  end

  private

  # -------------------------
  # Helpers
  # -------------------------

  def money(value)
    value.to_s.gsub(/[$,]/, '').to_f
  end

  def percentage(value)
    value.to_s.gsub('%', '').to_f
  end

  def safe_div(numerator, denominator)
    return 0 if denominator.to_f == 0
    numerator.to_f / denominator.to_f
  end

  def build_result(expected, actual, type: :money)
    expected = expected.round(2)
    actual   = actual.round(2)

    tolerance = type == :percent ? 0.5 : 1.0

    status = (expected - actual).abs <= tolerance ? "valid" : "invalid"

    {
        expected: expected,
        actual: actual,
        status: status
    }
  end

  # -------------------------
  # 1
  # -------------------------

  def validate_cms_reimbursement
    expected = money(@row["REIMBURSEMENT PER BILLING UNIT"]) *
               money(@row["BILLING UNIT PER PACKAGE SIZE"])

    actual = money(@row["CMS REIMBURSEMENT PER PACKAGE"])

    build_result(expected, actual)
  end

  # -------------------------
  # 2
  # -------------------------

  def validate_cost_per_unit_340b
    expected = safe_div(
      money(@row["COST 340B"]),
      money(@row["BILLING UNIT PER PACKAGE SIZE"])
    )

    actual = money(@row["COST PER UNIT 340B"])

    build_result(expected, actual)
  end

  # -------------------------
  # 3
  # -------------------------

  def validate_margin_340b
    expected = money(@row["CMS REIMBURSEMENT PER PACKAGE"]) -
               money(@row["COST 340B"])

    actual = money(@row["CMS MARGIN 340B COST"])

    build_result(expected, actual)
  end

  # -------------------------
  # 4
  # -------------------------

  def validate_percent_margin_340b
    expected = safe_div(
      money(@row["CMS MARGIN 340B COST"]),
      money(@row["COST 340B"])
    ) * 100

    actual = percentage(@row["CMS PERCENT MARGIN"])

    build_result(expected, actual)
  end

  # -------------------------
  # 5
  # -------------------------

  def validate_margin_gpo
    expected = money(@row["CMS REIMBURSEMENT PER PACKAGE"]) -
               money(@row["GPO COST"])

    actual = money(@row["CMS MARGIN GPO COST"])

    build_result(expected, actual)
  end

  # -------------------------
  # 6
  # -------------------------

  def validate_percent_margin_gpo
    expected = safe_div(
      money(@row["CMS MARGIN GPO COST"]),
      money(@row["GPO COST"])
    ) * 100

    actual = percentage(@row["GPO PERCENT MARGIN"])

    build_result(expected, actual)
  end

  # -------------------------
  # 7
  # -------------------------

  def validate_blended_percent_340b
    expected = safe_div(
      money(@row["BLENDED CMS MARGIN 340B COST"]),
      money(@row["BLENDED COST 340B"])
    ) * 100

    actual = percentage(@row["BLENDED CMS PERCENT MARGIN"])

    build_result(expected, actual)
  end

  # -------------------------
  # 8
  # -------------------------

  def validate_blended_percent_gpo
    expected = safe_div(
      money(@row["BLENDED CMS MARGIN GPO COST"]),
      money(@row["BLENDED GPO COST"])
    ) * 100

    actual = percentage(@row["BLENDED GPO PERCENT MARGIN"])

    build_result(expected, actual)
  end

end