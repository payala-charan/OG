module TallyValidationsHelper
  GROUPING_COLUMNS = [
    "GENERIC NAME",
    "FINANCIAL CLASS",
    "PRIMARY PAYOR NAME",
    "BENEFIT PLAN NAME",
    "HCPCS CODE",
    # "NDC CODE",
    "CHARGE CLASS",
    "PACKAGE SIZE"
  ].freeze

  SUMMATION_COLUMNS = [
    "TOTAL UNITS",
    "CMS TOTAL UNITS",
    "TOTAL PRODUCT COST",
    "TOTAL INSURANCE PAYMENT",
    "ACTUAL REIMBURSEMENT",
    "TOTAL MARGIN",
    "CONVERSION TOTAL PRODUCT COST",
    "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT",
    "CONVERSION PRODUCT TOTAL MARGIN",
    "BLENDED CONVERSION TOTAL PRODUCT COST",
    "BLENDED CONVERSION TOTAL MARGIN",
    "BLENDED CONVERSION COST DIFFERENCE",
    "BLENDED CONVERSION MARGIN DIFFERENCE"
  ].freeze

  COST_COLUMNS = [
    "PRODUCT COST PER UNIT",
    "CONVERSION PRODUCT COST PER UNIT"
  ].freeze

  PERCENTAGE_COLUMNS = [
    "PERCENT MARGIN",
    "CONVERSION PRODUCT PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
  ].freeze

  def grouping_columns
    GROUPING_COLUMNS
  end

  def summation_columns
    SUMMATION_COLUMNS
  end

  def cost_columns
    COST_COLUMNS
  end

  def percentage_columns
    PERCENTAGE_COLUMNS
  end

  def format_val(col, val)
    return "-" if val.nil?
    return val if val.is_a?(String)

    is_pct = PERCENTAGE_COLUMNS.include?(col)
    is_currency = col.include?("COST") || col.include?("PAYMENT") || col.include?("REIMBURSEMENT") || col.include?("MARGIN") || col.include?("DIFFERENCE")

    if is_pct
      "#{number_with_precision(val, precision: 2)}%"
    elsif is_currency
      prefix = val < 0 ? "-" : ""
      "#{prefix}$#{number_with_delimiter(number_with_precision(val.abs, precision: 2))}"
    else
      number_with_delimiter(val)
    end
  end
end
