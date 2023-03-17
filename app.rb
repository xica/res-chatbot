require "sinatra"
require "json"
require "logger"

require_relative "job"

ALLOW_CHANNEL_IDS = ENV.fetch("ALLOW_CHANNEL_IDS", "").split(/\s+|,\s*/)

def allowed_channel?(channel)
  if ALLOW_CHANNEL_IDS.empty?
    true
  else
    ALLOW_CHANNEL_IDS.include?(channel)
  end
end

logger = Logger.new(STDOUT)

slack_client = Slack::Web::Client.new
bot_info = slack_client.auth_test
bot_id = bot_info["user_id"]
logger.info "bot_id = #{bot_id}"

post "/slack/events" do
  request_data = JSON.parse(request.body.read)

  case request_data["type"]
  when "url_verification"
    request_data["challenge"]

  when "event_callback"
    event = request_data["event"]

    if event["type"] == "app_mention"
      message = event["text"]
      channel = event["channel"]

      if allowed_channel?(channel)
        logger.info "event: #{event.inspect}"
        logger.info "#{channel}: #{message}"
        case message
        when /^@chatgpt\s+/
          ChatGPTJob.perform_async({"channel" => channel, "message" => message})
        end
      end
    end

    status 200
  end
end
