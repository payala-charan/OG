# frozen_string_literal: true

# Loads Utilization Analytics from {BASE_URL}/api/utilization_analytics.
# This app renders the payload. It does not total, weight, or chart metrics itself.
# Every request sends team_id. It does not send user_id.
module UtilizationAnalytics
  TEAM_IDS = %w[198 209 147].freeze
  DEFAULT_TEAM_ID = "209"
end
