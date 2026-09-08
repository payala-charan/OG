# frozen_string_literal: true

class GmailExtraction < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  scope :recent, -> { order(created_at: :desc) }

  belongs_to :user
  belongs_to :gmail_connection
  has_many :gmail_extracted_emails, dependent: :delete_all

  validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :start_on, :end_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_on_not_before_start

  def end_on_not_before_start
    return if start_on.blank? || end_on.blank?

    errors.add(:end_on, "must be on or after start date") if end_on < start_on
  end
end
