# frozen_string_literal: true

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # sidekiq-unique-jobs: un retry no puede duplicar una llamada al LLM ni una
  # activación de step. El lock se declara por worker (`lock: :until_executed`).
  config.client_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Client }
  config.server_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Server }
  SidekiqUniqueJobs::Server.configure(config)
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
  config.client_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Client }
end
