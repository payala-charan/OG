# frozen_string_literal: true

class GmailOauthController < ApplicationController
  # OAuth GET returns here with omniauth.auth; require_login can redirect unauthenticated
  # users before the action and drop the one-time code — we handle that explicitly.
  skip_before_action :require_login, only: :callback

  def callback
    auth = request.env["omniauth.auth"]
    user = current_user
    if user.nil?
      return redirect_to login_path, alert: "Sign in first, then connect Gmail. Your Google return must be in the same session."
    end
    if auth.nil?
      return redirect_to gmail_extractions_path, alert: "Google sign-in was cancelled or failed."
    end

    creds = auth.credentials
    h = {
      access_token: creds.token,
      google_email: auth.info.email.to_s,
      token_expires_at: oauth_token_expires_at(creds)
    }
    h[:refresh_token] = creds.refresh_token if creds.refresh_token.present?

    conn = user.gmail_connection || user.build_gmail_connection
    if h[:refresh_token].blank? && conn.refresh_token.present?
      conn.update!(h.except(:refresh_token))
    else
      conn.update!(h)
    end
    if conn.refresh_token.blank?
      return redirect_to gmail_extractions_path, alert: "No refresh token from Google. In Google account → Security, revoke this app, then connect again and grant all requested permissions."
    end
    redirect_to gmail_extractions_path, notice: "Gmail is connected for #{conn.google_email}."
  end

  private

  def oauth_token_expires_at(credentials)
    exp = credentials.expires_at
    return nil if exp.blank?
    return exp if exp.is_a?(Time) || exp.is_a?(ActiveSupport::TimeWithZone)
    return Time.at(exp) if exp.is_a?(Integer) || exp.is_a?(Float) || (exp.is_a?(String) && exp.match?(/\A\d+(\.\d+)?\z/))

    Time.zone.parse(exp.to_s)
  rescue StandardError
    1.hour.from_now
  end
end
