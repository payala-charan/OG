# frozen_string_literal: true

class UtilizationAnalyticsController < ApplicationController
  def index
    @payload = UtilizationAnalytics::Client.new.fetch(analytics_query)
  rescue UtilizationAnalytics::Client::Unauthorized => error
    @error = error.message
    @payload = {}
    render status: :unauthorized
  rescue UtilizationAnalytics::Client::InvalidParams => error
    @error = error.message
    @payload = error.payload.is_a?(Hash) ? error.payload : {}
    render status: :unprocessable_entity
  rescue UtilizationAnalytics::Client::Error => error
    @error = error.message
    @payload = {}
    render status: :bad_gateway
  end

  def validate
    render json: UtilizationAnalytics::ValidationService.new(
      team_id: params[:team_id],
      params: params,
      analytics_data: analytics_param
    ).call
  rescue StandardError => error
    Rails.logger.error("[UtilizationAnalytics::Validation] #{error.class}: #{error.message}")
    render json: {
      "status" => "error",
      "message" => "Validation could not be completed. #{error.message}",
      "metrics" => []
    }
  end

  private

  def analytics_param
    raw = params[:analytics]
    return {} if raw.blank?
    return raw if raw.is_a?(String)
    return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)

    raw
  end

  def analytics_query
    UtilizationAnalytics::Query.build(
      team_id: params[:team_id],
      params: params,
      applied: analytics_applied?
    )
  end

  def analytics_applied?
    params[:analytics_request].present? || UtilizationAnalytics::Query.any_filter?(params)
  end
end
