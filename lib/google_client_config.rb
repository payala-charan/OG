# frozen_string_literal: true

# Centralizes Google API credentials (same as OmniAuth / Gmail API).
class GoogleClientConfig
  def self.client_id
    ENV.fetch("GOOGLE_CLIENT_ID")
  end

  def self.client_secret
    ENV.fetch("GOOGLE_CLIENT_SECRET")
  end
end
