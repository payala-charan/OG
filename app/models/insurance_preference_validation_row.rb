# frozen_string_literal: true

class InsurancePreferenceValidationRow < ApplicationRecord
  belongs_to :validation_run,
             class_name: "InsurancePreferenceValidationRun",
             foreign_key: :insurance_preference_validation_run_id,
             inverse_of: :validation_rows
  has_one :model_validation_result,
          class_name: "InsurancePreferenceModelResult",
          dependent: :destroy,
          inverse_of: :validation_row

  def missing_list
    parse_json_array(missing_insurances)
  end

  def extra_list
    parse_json_array(extra_insurances)
  end

  def spelling_list
    parse_json_array(spelling_mismatches)
  end

  def chip_kind
    case validation_status
    when "PASS" then "pass"
    when "REVIEW_SPELLING" then "review"
    when "FAIL_MISSING" then "fail"
    else "neutral"
    end
  end

  private

  def parse_json_array(value)
    return [] if value.blank?
    return value if value.is_a?(Array)

    JSON.parse(value)
  rescue JSON::ParserError
    value.to_s.split("\n").map(&:strip).reject(&:blank?)
  end
end
