require "slack-ruby-client"

Slack.configure do |config|
  config.token = ENV.fetch("SLACK_BOT_TOKEN", "SLACK_TOKEN_IS_NOT_GIVEN")
end

Slack::Events.configure do |config|
  config.signing_secret = ENV.fetch("SLACK_SIGNING_SECRET", "SLACK_SIGNING_SECRET_IS_NOT_GIVEN")
end
