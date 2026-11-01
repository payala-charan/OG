# frozen_string_literal: true

module FatValidation
  # Matches Overview rows by drug name, never by row position.
  class ValidationComparator
    def compare(actual_rows:, expected_rows:)
      expected_by_group = Array(expected_rows).index_by { |row| row[:generic_group].to_s }
      grouped = Array(actual_rows).group_by { |row| value(row, :generic_group).to_s }

      grouped.flat_map do |group, rows|
        if group.blank?
          rows.map { |row| result_for(row, nil, "FAIL", "Drug name was blank on the Overview table.") }
        elsif rows.size > 1
          rows.map do |row|
            result_for(row, expected_by_group[group], "DUPLICATE", "This drug name appears more than once on the Overview table.")
          end
        else
          [ compare_one(rows.first, expected_by_group[group]) ]
        end
      end
    end

    private

    def compare_one(actual, expected)
      actual_value = value(actual, :actual_value)
      expected_value = expected && expected[:expected_value]

      status, reason = if actual_value.nil?
        [ "FAIL", "Opportunity cell was empty." ]
      elsif expected.nil? || expected_value.nil?
        [ "MISSING_IN_SOURCE", "No database opportunity was calculated for this drug." ]
      elsif actual_value.to_i == expected_value.to_i
        [ "PASS", nil ]
      else
        [ "FAIL", "Opportunity does not match." ]
      end

      result_for(actual, expected, status, reason)
    end

    def result_for(actual, expected, status, reason)
      actual_value = value(actual, :actual_value)
      expected_value = expected && expected[:expected_value]
      difference = if actual_value.nil? || expected_value.nil?
        nil
      else
        actual_value.to_i - expected_value.to_i
      end

      {
        generic_group: value(actual, :generic_group).to_s.presence,
        column_name: FatValidation::OPPORTUNITY_COLUMN,
        expected_value: expected_value,
        actual_value: actual_value,
        difference: difference,
        status: status,
        details: (expected&.dig(:details) || {}).merge(
          "raw_actual" => value(actual, :raw_actual),
          "reason" => reason
        ).compact
      }
    end

    def value(row, key)
      row.respond_to?(key) ? row.public_send(key) : row[key]
    end
  end
end
