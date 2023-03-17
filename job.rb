require "sidekiq"
require "slack-ruby-client"

require_relative "chat-gpt"

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
    channel = params["channel"]
    user = params["user"]
    message = params["message"]

    answer = ChatGPT.chat_completion(message)

    response = "<@#{user}> #{answer}"

    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: response)
  end
end
