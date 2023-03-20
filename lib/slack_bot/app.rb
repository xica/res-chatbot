require "json"
require "logger"
require "sinatra/base"

require "slack_bot/jobs"

ALLOW_CHANNEL_IDS = ENV.fetch("ALLOW_CHANNEL_IDS", "").split(/\s+|,\s*/)

def allowed_channel?(channel)
  if ALLOW_CHANNEL_IDS.empty?
    true
  else
    ALLOW_CHANNEL_IDS.include?(channel)
  end
end

module SlackBot
  @logger = Logger.new(STDOUT)

  def self.logger
    @logger
  end

  Sidekiq.configure_client do |config|
    config.logger = logger
  end

  if ENV["APP_ENV"] == "test"
    logger.level = Logger::WARN
  end

  class Application < Sinatra::Base
    private_class_method def self.get_bot_id
      if ENV["APP_ENV"] == "test"
        "TEST_BOT_ID"
      else
        slack_client = Slack::Web::Client.new
        bot_info = slack_client.auth_test
        bot_info["user_id"]
      end
    end

    bot_id = get_bot_id
    SlackBot.logger.info "bot_id = #{bot_id}"

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
          user = event["user"]

          if allowed_channel?(channel)
            logger.info "event: #{event.inspect}"
            logger.info "#{channel}: #{message}"
            case message
            when /^<@#{bot_id}>\s+/
              message_body = Regexp.last_match.post_match
              ChatGPTJob.perform_async({
                "channel" => channel,
                "user" => user,
                "message" => message_body
              })
            end
          end
        end

        status 200
      end
    end

    post "/slack/commands/translate/:lang" do |lang|
      # {
      #   "token"=>"ois000000000000000000000",
      #   "team_id"=>"Txxxxxxxx",
      #   "team_domain"=>"mrkn",
      #   "channel_id"=>"Cxxxxxxxx",
      #   "channel_name"=>"random",
      #   "user_id"=>"Uxxxxxxxx",
      #   "user_name"=>"mrkn",
      #   "command"=>"/en",
      #   "text"=>"テストメッセージ",
      #   "api_app_id"=>"Axxxxxxxxxx",
      #   "is_enterprise_install"=>"false",
      #   "response_url"=>"https://hooks.slack.com/commands/Txxxxxxxx/4965584791638/xNA2z34Sb2RFpdcyjdIPwAz8",
      #   "trigger_id"=>"4957655817255.3234696253.bd659928b27b1da507f82fce3284fc43",
      #   "lang"=>"en"
      # }
      channel_id, user_id, text, lang = params.values_at("channel_id", "user_id", "text", "lang")

      if TranslateJob.lang_available?(lang)
        TranslateJob.perform_async({
          "channel" => channel_id,
          "user" => user_id,
          "lang" => lang,
          "text" => text
        })

        target_language = TranslateJob::TARGET_LANGUAGES[lang]
        quoted_text = text.each_line.map {|l| "> #{l}" }.join("")
        "Translating the following text to #{target_language}...\n#{quoted_text}"
      else
        "ERROR: Unsupported language code `#{lang}`"
      end
    end
  end
end
