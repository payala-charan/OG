# frozen_string_literal: true

require "google/apis/gmail_v1"

class GmailConnection < ApplicationRecord
  GMAIL_READ_SCOPE = "https://www.googleapis.com/auth/gmail.readonly"

  belongs_to :user
  has_many :gmail_extractions, dependent: :destroy

  def gmail_service
    ensure_valid_token!
    Google::Apis::GmailV1::GmailService.new.tap do |s|
      s.authorization = current_authorization
    end
  end

  def current_authorization
    Google::Auth::UserRefreshCredentials.new(
      client_id: GoogleClientConfig.client_id,
      client_secret: GoogleClientConfig.client_secret,
      scope: GMAIL_READ_SCOPE,
      access_token: access_token,
      refresh_token: refresh_token
    )
  end

  def ensure_valid_token!
    return if access_token.present? && token_expires_at && token_expires_at > 2.minutes.from_now

    if refresh_token.blank?
      raise "Gmail refresh token missing. Please reconnect your Google account."
    end

    c = Google::Auth::UserRefreshCredentials.new(
      client_id: GoogleClientConfig.client_id,
      client_secret: GoogleClientConfig.client_secret,
      scope: GMAIL_READ_SCOPE,
      access_token: access_token,
      refresh_token: refresh_token
    )
    c.fetch_access_token!
    new_exp = if c.respond_to?(:expires_in) && c.expires_in
      Time.current + c.expires_in
    elsif c.expires_at
      t = c.expires_at
      t.is_a?(Time) || t.is_a?(ActiveSupport::TimeWithZone) ? t : Time.at(t)
    else
      55.minutes.from_now
    end
    update!(
      access_token: c.access_token,
      token_expires_at: new_exp
    )
  end
end
