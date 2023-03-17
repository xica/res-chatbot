require "sidekiq"
require "slack-ruby-client"

redis_config = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

Slack.configure do |config|
  config.token = ENV["SLACK_BOT_TOKEN"]
end

class ChatGPTJob
  include Sidekiq::Job

  def perform(params)
    slack_client = Slack::Web::Client.new
    channel = params["channel"]
    user = params["user"]
    message = params["message"]
    response = "<@#{user}> Received: #{message.inspect} from #{channel} channel"
    client.chat_postMessage(channel: channel, text: response)
  end
end
