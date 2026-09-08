require 'bigdecimal'

class TallyValidationRecord < ApplicationRecord
  belongs_to :user
  validates :data, presence: true

  # Default columns to validate (as provided by the user)
  VALIDATE_COLUMNS = [
    'TOTAL UNITS',
    'CMS TOTAL UNITS',
    'TOTAL PRODUCT COST',
    'TOTAL INSURANCE PAYMENT',
    'ACTUAL REIMBURSEMENT',
    'TOTAL MARGIN',
    'CONVERSION TOTAL PRODUCT COST',
    'CONVERSION PRODUCT TOTAL INSURANCE PAYMENT',
    'CONVERSION PRODUCT TOTAL MARGIN',
    'BLENDED CONVERSION TOTAL PRODUCT COST',
    'BLENDED CONVERSION TOTAL MARGIN',
    'BLENDED CONVERSION COST DIFFERENCE',
    'BLENDED CONVERSION MARGIN DIFFERENCE'
  ].freeze

  # Parse a value into BigDecimal (tolerant of strings with commas/currency)
  def self.parse_number(value)
    return BigDecimal('0') if value.nil? || value.to_s.strip == ''
    s = value.to_s.strip
    # remove percentage signs, currency symbols, and thousand separators
    s = s.gsub(/[%$|,]/, '')
    # keep digits, minus and dot
    s = s.gsub(/[^0-9\-\.]/, '')
    return BigDecimal('0') if s == ''
    BigDecimal(s)
  rescue StandardError
    BigDecimal('0')
  end

  # Compute grouped sums from individual rows.
  # - individual_rows: array of hashes (column_name => value)
  # - group_keys: array of column names used to form the grouping key
  # - columns: array of column names to sum
  # Returns a hash keyed by composite group key => { column_name => BigDecimal(sum), '_group_values' => [values...] }
  def self.group_sums(individual_rows, group_keys, columns)
    sums = {}
    individual_rows.each do |row|
      key = group_keys.map { |k| (row[k] || '').to_s.strip }.join('||')
      sums[key] ||= Hash.new { |h, k| h[k] = BigDecimal('0') }
      columns.each do |col|
        sums[key][col] = sums[key][col] + parse_number(row[col])
      end
      sums[key]['_group_values'] ||= group_keys.map { |k| row[k].to_s }
    end
    sums
  end

  # Compare computed group sums against uploaded grouped rows.
  # - individual_rows: array of hashes
  # - grouped_rows: array of hashes (one row per group with aggregated values)
  # - group_keys: array of column names used to identify groups
  # - columns: array of column names to validate
  # - tolerance: numeric tolerance (absolute) for considering values equal
  # Returns an array of result hashes describing matches/mismatches.
  def self.compare_with_grouped(individual_rows, grouped_rows, group_keys:, columns: VALIDATE_COLUMNS, tolerance: 0)
    individual_sums = group_sums(individual_rows, group_keys, columns)

    grouped_index = {}
    grouped_rows.each do |row|
      key = group_keys.map { |k| (row[k] || '').to_s.strip }.join('||')
      grouped_index[key] = row
    end

    results = []
    (individual_sums.keys | grouped_index.keys).each do |key|
      indiv = individual_sums[key] || {}
      grouped_row = grouped_index[key] || {}
      columns.each do |col|
        indiv_val = indiv[col] || BigDecimal('0')
        grouped_val = parse_number(grouped_row[col])
        diff = indiv_val - grouped_val
        ok = diff.abs <= BigDecimal(tolerance.to_s)
        results << {
          group_key: key,
          group_values: indiv['_group_values'] || group_keys.map { |k| grouped_row[k].to_s },
          column: col,
          individual_sum: indiv_val.to_s('F'),
          grouped_value: grouped_val.to_s('F'),
          difference: diff.to_s('F'),
          ok: ok
        }
      end
    end

    results
  end

  # Instance helper: perform validation and persist results into `data` JSON column.
  # - individual_rows: array of hashes
  # - grouped_rows: array of hashes
  # - group_keys: array of grouping column names
  # - columns: optional array of columns to validate (defaults to VALIDATE_COLUMNS)
  # - tolerance: numeric tolerance for comparisons
  def perform_validation(individual_rows, grouped_rows, group_keys, columns: VALIDATE_COLUMNS, tolerance: 0)
    results = self.class.compare_with_grouped(individual_rows, grouped_rows, group_keys: group_keys, columns: columns, tolerance: tolerance)
    self.data = { validated_at: Time.current, group_keys: group_keys, columns: columns, tolerance: tolerance, results: results }
    save!
    results
  end
end
