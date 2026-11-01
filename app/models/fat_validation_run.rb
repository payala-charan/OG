# frozen_string_literal: true

class FatValidationRun < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :highlight_screenshot
  has_many :results,
           class_name: "FatValidationResult",
           dependent: :destroy,
           inverse_of: :fat_validation_run

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }

  ENVIRONMENTS = FatValidation::FatEnvironment::ENVIRONMENTS.keys.freeze
  REPORT_TYPES = %w[overview margin utilization].freeze
  DATA_SOURCES = %w[database excel].freeze

  validates :team_id, inclusion: { in: FatValidation::FatEnvironment::TEAMS.keys }
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :report_type, inclusion: { in: REPORT_TYPES }
  validates :data_source, inclusion: { in: DATA_SOURCES }
  validates :status, presence: true

  def self.latest_completed_for(team_id:, environment:, report_type:)
    completed
      .where(team_id: team_id.to_s, environment: environment.to_s, report_type: report_type.to_s)
      .order(completed_at: :desc, id: :desc)
      .first
  end

  def status_payload
    {
      id: id,
      status: status,
      progress_message: progress_message,
      error_message: error_message,
      team_id: team_id,
      environment: environment,
      report_type: report_type,
      data_source: data_source,
      accounting_period_id: accounting_period_id,
      total_records: total_records,
      passed_records: passed_records,
      failed_records: failed_records,
      started_at: started_at,
      completed_at: completed_at,
      screenshot_ready: highlight_screenshot.attached?
    }
  end
end
