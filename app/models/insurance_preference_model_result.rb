# frozen_string_literal: true

class InsurancePreferenceModelResult < ApplicationRecord
  belongs_to :validation_row,
             class_name: "InsurancePreferenceValidationRow",
             foreign_key: :insurance_preference_validation_row_id,
             inverse_of: :model_validation_result
end
