# frozen_string_literal: true

# Global OmniAuth failure callback (e.g. Google, GitHub)
class OauthController < ActionController::Base
  def failure
    flash[:alert] = "Authentication failed: #{params[:message].presence || 'Error'}. Try again."
    redirect_to "/login"
  end
end
