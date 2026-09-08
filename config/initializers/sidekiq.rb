# frozen_string_literal: true

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url, network_timeout: 5, pool_timeout: 5 }
end

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url, network_timeout: 5, pool_timeout: 5 }
end
