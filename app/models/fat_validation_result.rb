# frozen_string_literal: true

class FatValidationResult < ApplicationRecord
  STATUSES = %w[PASS FAIL DUPLICATE MISSING_IN_SOURCE MISSING_IN_FAT].freeze

  belongs_to :fat_validation_run, inverse_of: :results

  validates :column_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  def pass?
    status == "PASS"
  end
end
