require "json"
require "logger"

require "sinatra/base"
require 'sinatra/custom_logger'

require "slack_bot/jobs"

ALLOW_CHANNEL_IDS = ENV.fetch("ALLOW_CHANNEL_IDS", "").split(/\s+|,\s*/)

def allowed_channel?(channel)
  if ALLOW_CHANNEL_IDS.empty?
    true
  else
    ALLOW_CHANNEL_IDS.include?(channel)
  end
end

def thread_context_prohibited?(channel)
  true
end

module SlackBot
  class Application < Sinatra::Base
    helpers Sinatra::CustomLogger

    configure :development, :production do
      logger = Logger.new(STDERR)
      logger.level = Logger::WARN if test?
      logger.level = Logger::DEBUG if development?
      set :logger, logger
    end

    configure :test do
      set :logger, Rack::NullLogger.new(self)
    end

    Sidekiq.configure_client do |config|
      config.logger = logger
    end

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
    logger.info "bot_id = #{bot_id}"

    post "/slack/events" do
      request_data = JSON.parse(request.body.read)

      case request_data["type"]
      when "url_verification"
        request_data["challenge"]

      when "event_callback"
        event = request_data["event"]

        # Non-thread message:
        # {"client_msg_id"=>"58e6675f-c164-451a-8354-7c7085ddba33",
        #  "type"=>"app_mention",
        #  "text"=>"<@U04U7QNHCD9> 以下を日本語に翻訳してください:\n" + "\n" + "Brands and...",
        #  "user"=>"U036WLG7H",
        #  "ts"=>"1679639978.922569",
        #  "blocks"=>
        #   [{"type"=>"rich_text",
        #     "block_id"=>"G8jBl",
        #     "elements"=>
        #      [{"type"=>"rich_text_section",
        #        "elements"=>
        #         [{"type"=>"user", "user_id"=>"U04U7QNHCD9"},
        #          {"type"=>"text",
        #           "text"=>" 以下を日本語に翻訳してください:\n" + "\n" + "Brands and..."}]}]}],
        #  "team"=>"T036WLG7F",
        #  "channel"=>"C036WLG7Z",
        #  "event_ts"=>"1679639978.922569"}

        # Reply in thread:
        # {"client_msg_id"=>"56846932-4600-4161-9947-a164084bf559",
        #  "type"=>"app_mention",
        #  "text"=>"<@U04U7QNHCD9> スレッド返信のテストです。",
        #  "user"=>"U036WLG7H",
        #  "ts"=>"1679644228.326869",
        #  "blocks"=>
        #   [{"type"=>"rich_text",
        #     "block_id"=>"EHX",
        #     "elements"=>
        #      [{"type"=>"rich_text_section",
        #        "elements"=>
        #         [{"type"=>"user", "user_id"=>"U04U7QNHCD9"},
        #          {"type"=>"text", "text"=>" スレッド返信のテストです。"}]}]}],
        #  "team"=>"T036WLG7F",
        #  "thread_ts"=>"1679640009.398859",
        #  "parent_user_id"=>"U04U7QNHCD9",
        #  "channel"=>"C036WLG7Z",
        #  "event_ts"=>"1679644228.326869"}

        if event["type"] == "app_mention"
          team = event["team"]
          channel = event["channel"]
          user = event["user"]
          ts = event["ts"]
          thread_ts = event["thread_ts"]
          message = event["text"]

          if allowed_channel?(channel)
            logger.info "Event:\n" + event.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")
            logger.info "#{channel}: #{message}"

            if thread_ts && thread_context_prohibited?(channel)
              response = "Sorry, we can't continue the conversation within threads on this channel! Please mention me outside threads."
              Utils.post_ephemeral(
                channel: channel,
                user: user,
                thread_ts: ts,
                text: response,
                blocks: [
                  {
                    type: "section",
                    text: {
                      type: "mrkdwn",
                      text: "*#{response}*"
                    }
                  }
                ]
              )
            else
              case message
              when /^<@#{bot_id}>\s+/
                message_body = Regexp.last_match.post_match
                job_params = {
                  "channel" => channel,
                  "user" => user,
                  "ts" => ts,
                  "message" => message_body,
                }
                params["thread_ts"] = thread_ts if thread_ts
                ChatGPTJob.perform_async(job_params)
              end
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

    post "/slack/interaction" do
      payload = JSON.load(params["payload"])
      payload_json = JSON.generate(payload, indent: "  ", space: " ", object_nl: "\n", array_nl: "\n")
      logger.info "Payload:\n" + payload_json.each_line.map {|l| "> #{l}" }.join("")

      # response_url = payload["response_url"]
      # response = Faraday.post(response_url) do |request|
      #   request.headers = {
      #     "Content-Type" => "application/json",
      #   }
      #   request.body = {
      #     text: "Interaction has been received"
      #   }.to_json
      # end

      status 200
    end
  end
end
