require "json"
require "logger"

require "sinatra/base"
require 'sinatra/custom_logger'

module SlackBot
  class Application < Sinatra::Base
    helpers Sinatra::CustomLogger

    set :logger, Rails.logger

    private def bot_id
      @bot_id ||= fetch_bot_id
    end

    private def fetch_bot_id
      bot_id = if ENV["APP_ENV"] == "test"
                 "TEST_BOT_ID"
               else
                 slack_client = Slack::Web::Client.new
                 bot_info = slack_client.auth_test
                 bot_info["user_id"]
               end
    ensure
      logger.info "bot_id = #{bot_id}"
    end

    ALLOW_CHANNEL_IDS = ENV.fetch("ALLOW_CHANNEL_IDS", "").split(/\s+|,\s*/)
    MAGELLAN_RAG_CHANNEL_IDS = ENV.fetch("MAGELLAN_RAG_CHANNEL_IDS", "").split(/\s+|,\s*/)
    MAGELLAN_RAG_ENDPOINT = ENV.fetch("MAGELLAN_RAG_ENDPOINT", "localhost:12345")
    REGULATION_RAG_CHANNEL_IDS = ENV.fetch("REGULATION_RAG_CHANNEL_IDS", "C07V94148PK C087CJU8E1E").split(/\s+|,\s*/)

    [
      :ALLOW_CHANNEL_IDS,
      :MAGELLAN_RAG_CHANNEL_IDS,
      :MAGELLAN_RAG_ENDPOINT,
      :REGULATION_RAG_CHANNEL_IDS,
    ].each do |name|
      value = const_get(name)
      logger.info "#{name}: #{value.inspect}"
    end

    private def allowed_channel?(channel)
      if ALLOW_CHANNEL_IDS.empty?
        true
      else
        ALLOW_CHANNEL_IDS.include?(channel.slack_id)
      end
    end

    private def magellan_rag_channel?(channel)
      if MAGELLAN_RAG_CHANNEL_IDS.empty?
        false
      else
        MAGELLAN_RAG_CHANNEL_IDS.include?(channel.slack_id)
      end
    end

    private def regulation_rag_channel?(channel)
      if REGULATION_RAG_CHANNEL_IDS.empty?
        false
      else
        REGULATION_RAG_CHANNEL_IDS.include?(channel.slack_id)
      end
    end

    private def thread_allowed_channel?(channel)
      true # channel.thread_allowed?
    end

    before "/events" do
      verify_slack_request!
    end

    before "/interactions" do
      verify_slack_request!
    end

    private def verify_slack_request!
      slack_request = Slack::Events::Request.new(request)
      slack_request.verify!
    end

    error Slack::Events::Request::MissingSigningSecret do
      status 500
    end

    error Slack::Events::Request::InvalidSignature do
      status 400
    end

    def mention?(event)
      event["type"] == "app_mention"
    end

    def direct_message?(event)
      event["type"] == "message" && event["channel_type"] == "im"
    end

    post "/events" do
      request_data = JSON.parse(request.body.read)

      case request_data["type"]
      when "url_verification"
        request_data["challenge"]

      when "event_callback"
        event = request_data["event"]

        # Non-thread message: {{{
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
        # }}}

        # Reply in thread: {{{
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
        # }}}

        if mention?(event) || direct_message?(event)
          channel = ensure_conversation(event["channel"])
          user = ensure_user(event["user"], channel)
          ts = event["ts"]
          thread_ts = event["thread_ts"]
          text = event["text"]

          begin
            case
            when magellan_rag_channel?(channel)
              logger.info "Event:\n" + event.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")
              logger.info "#{channel.slack_id}: #{text}"
              if thread_ts and not thread_allowed_channel?(channel)
                notify_do_not_allowed_thread_context(channel, user, ts)
              else
                process_magellan_rag_message(channel, user, ts, thread_ts, text)
              end
            when regulation_rag_channel?(channel)
              logger.info "Event:\n" + event.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")
              logger.info "#{channel.slack_id}: #{text}"
              if thread_ts and not thread_allowed_channel?(channel)
                notify_do_not_allowed_thread_context(channel, user, ts)
              else
                process_regulation_rag_message(channel, user, ts, thread_ts, text)
              end
            when allowed_channel?(channel)
              logger.info "Event:\n" + event.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")
              logger.info "#{channel.slack_id}: #{text}"

              if thread_ts and not thread_allowed_channel?(channel)
                notify_do_not_allowed_thread_context(channel, user, ts)
              else
                process_message(channel, user, ts, thread_ts, text)
              end
            else
              logger.info "A message coming from the channel #{channel.slack_id} is ignored."
            end
          rescue Exception => err
            Utils.post_message(
              channel: channel.slack_id,
              thread_ts: thread_ts,
              text: [
                ":bangbang: *ERROR*: #{err.message}",
                *err.backtrace
              ].join("\n"),
              mrkdwn: true
            )
          end
        end

        status 200
      end
    end

    post "/interactions" do
      payload = JSON.parse(params["payload"])
      case payload["type"]
      when "block_actions"
        # Example payload: {{{
        # {"type"=>"block_actions",
        #  "user"=>
        #   {"id"=>"U02M703H8UD",
        #    "username"=>"mrkn832",
        #    "name"=>"mrkn832",
        #    "team_id"=>"T036WLG7F"},
        #  "api_app_id"=>"A04UXJQGE8G",
        #  "token"=>"ois0a7oRraM5473ru1fMXzYL",
        #  "container"=>
        #   {"type"=>"message",
        #    "message_ts"=>"1680167961.051859",
        #    "channel_id"=>"C036WLG7Z",
        #    "is_ephemeral"=>false,
        #    "thread_ts"=>"1680167953.226819"},
        #  "trigger_id"=>"5036827519765.3234696253.771f51c31efbc827286c0a43befd4251",
        #  "team"=>{"id"=>"T036WLG7F", "domain"=>"mrkn"},
        #  "enterprise"=>nil,
        #  "is_enterprise_install"=>false,
        #  "channel"=>{"id"=>"C036WLG7Z", "name"=>"random"},
        #  "message"=>
        #   {"bot_id"=>"B04UXK8GLG0",
        #    "type"=>"message",
        #    "text"=>"<@U036WLG7H> 苺大福の発祥地は日本であり、正確な起源は不明ですが、江戸時代にはすでに存在していたとされています。",
        #    "user"=>"U04U7QNHCD9",
        #    "ts"=>"1680167961.051859",
        #    "app_id"=>"A04UXJQGE8G",
        #    "blocks"=>
        #     [{"type"=>"section",
        #       "block_id"=>"pv1td",
        #       "text"=>
        #        {"type"=>"mrkdwn",
        #         "text"=>
        #          "<@U036WLG7H> 苺大福の発祥地は日本であり、正確な起源は不明ですが、江戸時代にはすでに存在していたとされています。",
        #         "verbatim"=>false}},
        #      {"type"=>"context",
        #       "block_id"=>"E6OL",
        #       "elements"=>
        #        [{"type"=>"mrkdwn",
        #          "text"=>
        #           "API Usage: total 102 tokens ≈ ¥0.03 (prompt + completion = 54 + 48 tokens ≈ ¥0.02 + ¥0.01)",
        #          "verbatim"=>false}]},
        #      {"type"=>"actions",
        #       "block_id"=>"t53",
        #       "elements"=>
        #        [{"type"=>"button",
        #          "action_id"=>"gF=p",
        #          "text"=>{"type"=>"plain_text", "text"=>"Good", "emoji"=>true},
        #          "style"=>"primary",
        #          "value"=>"good"},
        #         {"type"=>"button",
        #          "action_id"=>"/ba",
        #          "text"=>{"type"=>"plain_text", "text"=>"Bad", "emoji"=>true},
        #          "style"=>"danger",
        #          "value"=>"bad"}]}],
        #    "team"=>"T036WLG7F",
        #    "thread_ts"=>"1680167953.226819",
        #    "parent_user_id"=>"U036WLG7H"},
        #  "state"=>{"values"=>{}},
        #  "response_url"=>
        #   "https://hooks.slack.com/actions/T036WLG7F/5063466698576/KHj1F2n100Ouy1pf7leGRqdW",
        #  "actions"=>
        #   [{"action_id"=>"gF=p",
        #     "block_id"=>"t53",
        #     "text"=>{"type"=>"plain_text", "text"=>"Good", "emoji"=>true},
        #     "value"=>"good",
        #     "style"=>"primary",
        #     "type"=>"button",
        #     "action_ts"=>"1680230940.375437"}]}
        # }}}

        feedback_value = payload.dig("actions", 0, "value")
        response = Response.find_by!(slack_ts: payload["message"]["ts"])

        Response.transaction do
          Faraday.post(payload["response_url"]) do |request|
            request.headers = {
              "Content-Type" => "application/json"
            }
            body = {
              "text" => payload.dig("message", "text"),
              "blocks" => payload.dig("message", "blocks"),
            }
            feedback_block = body["blocks"][-1]
            if feedback_block["type"] != "context"
              feedback_block = {}
              body["blocks"] << feedback_block
            end
            feedback_block.update({
              "type" => "context",
              "elements" => [
                {
                  "type" => "mrkdwn",
                  "text" => "#{feedback_value.capitalize} feedback received."
                }
              ]
            })
            request.body = body.to_json
          end

          response.good = (feedback_value == "good")
          response.save!
        end
      end

      status 200
    end

    private def ensure_user(user_id, channel)
      user = User.find_by_slack_id(user_id)
      user = fetch_user!(user_id) if user.blank?
      unless channel.members.include?(user)
        channel.members << user
      end
      user
    end

    private def ensure_conversation(channel_id)
      channel = Conversation.find_by_slack_id(channel_id)
      if channel.present?
        channel
      else
        fetch_conversation!(channel_id)
      end
    end

    private def fetch_user!(user_id)
      slack_client = Slack::Web::Client.new
      response = slack_client.users_info(user: user_id, include_locale: true)
      if response.ok
        User.create!(
          name: response.user.name,
          real_name: response.user.real_name,
          slack_id: response.user.id,
          locale: response.user.locale,
          email: response.user.profile.email,
          tz_offset: response.user.tz_offset.to_i
        )
      else
        raise "users.info with user=#{user_id} is failed"
      end
    end

    private def fetch_conversation!(channel_id)
      logger.info "[fetch_conversation!] channel_id=#{channel_id}"
      slack_client = Slack::Web::Client.new
      response = slack_client.conversations_info(channel: channel_id)
      if response.ok
        Conversation.create!(
          name: response.channel.name,
          slack_id: response.channel.id
        )
      else
        raise "conversations.info with channel=#{channel_id} is failed"
      end
    end

    private def notify_do_not_allowed_thread_context(channel, user, ts)
      reply_as_ephemeral(channel, user, ts, "Sorry, we can't continue the conversation within threads on this channel! Please mention me outside threads.")
    end

    private def reply_as_ephemeral(channel, user, ts, message)
      Utils.post_ephemeral(
        channel: channel.slack_id,
        user: user.slack_id,
        thread_ts: ts,
        text: message,
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*#{message}*"
            }
          }
        ]
      )
    end

    private def process_message(channel, user, ts, thread_ts, text)
      return unless text =~ /^<@#{bot_id}>\s+/

      message_body = Regexp.last_match.post_match

      options = process_options(message_body)
      return if options.nil?

      begin
        options.validate!
      rescue ChatCompletionJob::InvalidOptionError => error
        reply_as_ephemeral(channel, user, ts, error.message)
        return
      end

      message = Message.create!(
        conversation: channel,
        user: user,
        text: message_body,
        slack_ts: ts,
        slack_thread_ts: thread_ts || ts
      )
      ChatCompletionJob.perform_later("message_id" => message.id, "options" => options.to_h)
    end

    private def process_options(message_body)
      first_line = message_body.each_line.first
      rest_lines = message_body[(first_line.length + 1) ..]

      options = ChatCompletionJob::Options.new
      return options unless first_line.match? /\A--\w+/

      args = first_line.strip.split(" ")
      args.each do |arg|
        case arg
        # when "--set-channel-prompt"
        #   set_channel_prompt(channel, rest_lines)
        # when "--unset-channel-prompt"
        #   set_channel_prompt(channel)
        when "--allow-thread"
          allow_thread(channel)
          return nil
        when "--disallow-thread"
          disallow_thread(channel)
          return nil
        when /\A--temperature=(\d+\.\d+)\z/
          options.temperature = $1.to_f
        when /\A--top-p=(1\.0|0\.\d+)\z/
          options.top_p = $1.to_f
        when /\A--model=(gpt-\S+)\z/
          options.model = $1
        when /\A--no-default-prompt\z/
          options.no_default_prompt = true
        end
      end

      options
    end

    private def process_magellan_rag_message(channel, user, ts, thread_ts, text)
      logger.info "process_magellan_rag_message: channel=#{channel.slack_id}, user=#{user.slack_id}, ts=#{ts}, thread_ts=#{thread_ts}, text=#{text}"
      return unless text =~ /^<@#{bot_id}>\s+/

      message_body = Regexp.last_match.post_match
      options, message_body = process_magellan_rag_options(message_body)
      logger.info "process_magellan_rag_message: options=#{options}"
      return if options.nil?

      begin
        options.validate!
      rescue MagellanRagQueryJob::InvalidOptionError => error
        logger.warn "process_magellan_rag_message: options.validate! failed"
        reply_as_ephemeral(channel, user, ts, error.message)
        return
      end

      message = Message.create!(
        conversation: channel,
        user: user,
        text: message_body,
        slack_ts: ts,
        slack_thread_ts: thread_ts || ts
      )
      logger.info "process_magellan_rag_message: message=#{message}"
      MagellanRagQueryJob.perform_later("message_id" => message.id, "options" => options.to_h)
    end

    private def process_magellan_rag_options(message_body)
      first_line = message_body.each_line.first
      rest_lines = message_body[(first_line.length + 1)..]

      options = MagellanRagQueryJob::Options.new
      return options, message_body unless first_line.match? /\A--\w+/

      args = first_line.strip.split(" ")
      not_args = []
      args.each do |arg|
        case arg
        when "--retrieval"
          options.retrieval_only = true
        else
          not_args << arg
        end
      end

      first_line = not_args.join(" ")
      message_body = [first_line, rest_lines].join("\n").strip
      [options, message_body]
    end

    private def process_regulation_rag_message(channel, user, ts, thread_ts, text)
      return unless text =~ /^<@#{bot_id}>\s+/

      logger.info "process_regulation_rag_message: channel=#{channel.slack_id}, user=#{user.slack_id}, ts=#{ts}, thread_ts=#{thread_ts}, text=#{text}"
      message_body = Regexp.last_match.post_match
      options, message_body = process_regulation_rag_options(message_body)
      logger.info "process_regulation_rag_message: options=#{options}"
      return if options.nil?

      # No options now
      # begin
      #   options.validate!
      # rescue MagellanRagQueryJob::InvalidOptionError => error
      #   logger.warn "process_magellan_rag_message: options.validate! failed"
      #   reply_as_ephemeral(channel, user, ts, error.message)
      #   return
      # end

      # TODO: Insert message into OpenSearch
      message = Message.create!(
        conversation: channel,
        user: user,
        text: message_body,
        slack_ts: ts,
        slack_thread_ts: thread_ts || ts
      )
      logger.info "process_magellan_rag_message: message=#{message}"
      RegulationRagQueryJob.perform_later("message_id" => message.id)
    end

    private def process_regulation_rag_options(message_body)
      [true, message_body]  # No options
    end

    private def check_command_permission!(channel, user)
      # TODO
    end

    # private def set_channel_prompt(channel, user, prompt)
    #   check_command_permission!(channel, user)
    #   # TODO
    # end

    # private def unset_channel_prompt(channel, user, prompt)
    #   check_command_permission!(channel, user)
    #   # TODO
    # end

    private def allow_thread(channel, user)
      check_command_permission!(channel, user)
      channel.update!(thread_allowed: true)
    end

    private def disallow_thread(channel, user)
      check_command_permission!(channel, user)
      channel.update!(thread_allowed: false)
    end
  end
end
