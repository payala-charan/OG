# frozen_string_literal: true

class InsurancePreferenceValidationRun < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :master_file
  has_one_attached :biosimilar_file
  has_one_attached :output_file
  has_many :validation_rows,
           class_name: "InsurancePreferenceValidationRow",
           dependent: :destroy,
           inverse_of: :validation_run
  has_many :model_validation_results, through: :validation_rows, source: :model_validation_result

  attribute :model_validation_enabled, :boolean, default: false

  enum :status, {
    pending: 0,
    parsing: 1,
    validating: 2,
    model_validating: 3,
    complete: 4,
    failed: 5
  }

  def status_payload
    {
      id: id,
      status: status,
      progress_message: progress_message,
      error_message: error_message,
      model_validation_enabled: model_validation_enabled,
      warnings: warnings,
      summary: summary,
      download_ready: complete? && output_file.attached?,
      row_count: validation_rows.count
    }
  end
end
