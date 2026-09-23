module ValidationComparison
  INSURANCE_PAYMENT_COLUMNS = [
    "TOTAL INSURANCE PAYMENT",
    "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT"
  ].freeze

  EXACT_TOLERANCE = 0.01
  DEFAULT_CLOSE_TOLERANCE = 1.001
  INSURANCE_NEAREST_TOLERANCE = 20.0

  module_function

  def status(actual, calc, column = nil)
    diff = (numeric_value(actual).round(2) - numeric_value(calc).round(2)).abs

    if diff < EXACT_TOLERANCE
      "exact"
    elsif insurance_payment_column?(column) && diff <= INSURANCE_NEAREST_TOLERANCE
      "nearest"
    elsif !insurance_payment_column?(column) && diff <= DEFAULT_CLOSE_TOLERANCE
      "close"
    else
      "error"
    end
  end

  def match?(actual, calc, column = nil)
    status(actual, calc, column) != "error"
  end

  def cell_match?(header, cell)
    return false unless cell.is_a?(Hash)

    if insurance_payment_column?(header)
      match?(cell["actual"] || cell[:actual], cell["calc"] || cell[:calc], header)
    else
      cell["match"] || cell[:match]
    end
  end

  def cell_status(header, cell)
    return "error" unless cell.is_a?(Hash)

    if insurance_payment_column?(header)
      status(cell["actual"] || cell[:actual], cell["calc"] || cell[:calc], header)
    else
      cell["status"] || cell[:status] || ((cell["match"] || cell[:match]) ? "exact" : "error")
    end
  end

  def insurance_payment_column?(column)
    INSURANCE_PAYMENT_COLUMNS.include?(column.to_s)
  end

  def numeric_value(value)
    value.to_s.gsub(/[\$,()%]/, "").strip.to_f
  rescue
    0.0
  end
end
