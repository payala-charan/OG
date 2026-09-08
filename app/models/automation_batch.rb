class AutomationBatch < ApplicationRecord
  belongs_to :automation_schedule, optional: true
  has_many :automation_batch_items, dependent: :destroy

  before_validation :set_batch_type, on: :create
  validates :batch_type, inclusion: { in: %w[utilization ranking] }

  def check_completion_and_notify!
    send_email = false

    AutomationBatch.transaction do
      lock!
      if completed_jobs + failed_jobs >= total_jobs
        unless ['completed', 'partially_failed'].include?(status)
          final_status = failed_jobs > 0 ? 'partially_failed' : 'completed'
          update!(status: final_status)
          send_email = failed_jobs > 0
        end
      end
    end

    # Perform the HTTP call outside the transaction block to avoid locking the DB
    send_error_email if send_email
  end

  private

  def send_error_email
    emails = AlertEmail.pluck(:email)
    return if emails.empty?

    failed_items = automation_batch_items.where(status: 'failed')
    return if failed_items.empty?

    details_array = failed_items.map do |item|
      "Team: #{item.team_id} | Quarter #{item.quarter}\t#{item.error_message || 'file not found'}\n#{item.generic_name_group}"
    end

    summary_details = details_array.take(15).join("\n")
    summary_details += "\n... and #{details_array.size - 15} more errors." if details_array.size > 15

    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI('https://api.emailjs.com/api/v1.0/email/send')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path, { 
      'Content-Type' => 'application/json',
      'Origin' => 'http://localhost:1234',
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    })
    request.body = {
      service_id: 'service_vu39hfl',
      template_id: 'template_sm4bk8h',
      user_id: 'IW-5qyDYUvTL8TLNo',
      template_params: {
        to_emails: emails.join(','),
        error_details: summary_details
      }
    }.to_json

    begin
      http.request(request)
    rescue => e
      Rails.logger.error "EmailJS sending failed: #{e.message}"
    end
  end

  def set_batch_type
    return if batch_type.present?
    
    # If the association is loaded or can be fetched
    schedule = automation_schedule || AutomationSchedule.find_by(id: automation_schedule_id)
    self.batch_type = schedule&.schedule_type || 'utilization'
  end
end
