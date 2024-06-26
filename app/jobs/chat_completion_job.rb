require "slack_bot/utils"
require "utils"

class ChatCompletionJob < SlackResponseJob
  queue_as :default

  VALID_MODELS = [
    # OpenAI API
    "gpt-3.5-turbo".freeze,
    "gpt-3.5-turbo-0301".freeze,
    "gpt-4".freeze,
    "gpt-4-0314".freeze,
    "gpt-4o".freeze,

    # Azure OpenAI Service
    /\bgpt-35-turbo\b/.freeze,
  ].freeze

  DEFAULT_MODEL = ENV.fetch("DEFAULT_MODEL", VALID_MODELS[0])

  class InvalidOptionError < StandardError; end

  Options = Struct.new(
    :model,
    :temperature,
    :top_p,
    :no_default_prompt,
    keyword_init: true
  ) do
    def validate!
      validate_model! unless model.nil?
      validate_temperature! unless temperature.nil?
      validate_top_p! unless top_p.nil?
    end

    def validate_model!
      if OpenAI.configuration.api_type == :azure
        return if model.nil?
      else
        ChatCompletionJob::VALID_MODELS.each do |valid_model|
          case valid_model
          when Regexp
            return if valid_model.match?(model)
          else
            return if model == valid_model
          end
        end
      end
      raise InvalidOptionError, "Invalid model is specified: #{model}"
    end

    def validate_temperature!
      unless 0 <= temperature && temperature <= 2
        raise InvalidOptionError, "Temperature must be in 0..2"
      end
    end

    def validate_top_p!
      unless 0 <= top_p && top_p <= 1
        raise InvalidOptionError, "Top_p must be in 0..1"
      end
    end
  end

  DEFAULT_REACTION_SYMBOL = "hourglass_flowing_sand".freeze
  REACTION_SYMBOL = ENV.fetch("SLACK_REACTION_SYMBOL", DEFAULT_REACTION_SYMBOL)
  ERROR_REACTION_SYMBOL = "bangbang".freeze

  def model_for_message(message)
    message.conversation.model || DEFAULT_MODEL
  end

  def perform(params)
    if params["message_id"].blank?
      logger.warn "Empty message_id is given"
      return
    end

    message = Message.find(params["message_id"])
    if message.blank?
      logger.warn "Unable to find Message with id=#{message_id}"
      return
    end

    if message.query.present?
      logger.warn "Message with id=#{message.id} already has its query and response"
      return
    end

    options = Options.new(**params.fetch("options", {}))

    begin
      start_query(message)
      process_query(message, options)
    ensure
      finish_query(message)
    end
  rescue Exception => error
    logger.error "ERROR: #{error.message}"
    raise unless Rails.env.production?
  end

  private def process_query(message, options)
    messages = if message.slack_ts == message.slack_thread_ts
                 prompt = if options.no_default_prompt
                            ""
                          else
                            Utils.default_prompt
                          end
                 Utils.make_first_messages(prompt, message.text)
               else
                 Utils.make_thread_context(message)
               end
    logger.info "Query Messages:\n" + messages.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")

    model = options.model || model_for_message(message)
    temperature = options.temperature || 0.7

    query = Query.new(
      message: message,
      text: messages[-1]["content"],
      body: {
        parameters: {
          model: model,
          messages: messages,
          temperature: temperature
        }
      }
    )
    # TODO: resolve the duplicate of the above query construction and Utils.chat_completion method.
    # The best way may be making Utils.chat_completion a Query's instance method.

    chat_response = Utils.chat_completion(*messages, model:, temperature:)
    logger.info "Chat Response:\n" + chat_response.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")

    unless chat_response.key? "choices"
      if chat_response.key? "error"
        # Error case:
        #
        # {"error"=>
        #   {"message"=>
        #     "You exceeded your current quota, please check your plan and billing details.",
        #    "type"=>"insufficient_quota",
        #    "param"=>nil,
        #    "code"=>nil}}

        error_type, error_message = chat_response["error"].values_at("type", "message")
        Utils.post_message(
          channel: message.conversation.slack_id,
          thread_ts: message.slack_thread_ts,
          text: ":#{ERROR_REACTION_SYMBOL}: *ERROR*: #{error_type}: #{error_message}",
          mrkdwn: true
        )
      else
        Utils.post_message(
          channel: message.conversation.slack_id,
          thread_ts: message.slack_thread_ts,
          text: ":#{ERROR_REACTION_SYMBOL}: *ERROR*: #{chat_response.inspect}",
          mrkdwn: true
        )
      end
      error_query(message)
      return
    end

    # Regular case:
    #
    # {"id"=>"chatcmpl-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    #  "object"=>"chat.completion",
    #  "created"=>1679624074,
    #  "model"=>"gpt-3.5-turbo-0301",
    #  "usage"=>{"prompt_tokens"=>73, "completion_tokens"=>77, "total_tokens"=>150},
    #  "choices"=>
    #   [{"message"=>
    #      {"role"=>"assistant",
    #       "content"=>
    #        "はい、正しいです。ChatGPTはオープンAIによってトレーニングされた大規模な言語モデルであり、インターネットから情報を取得することができます。現在の日付は2023年3月24日です。"},
    #     "finish_reason"=>"stop",
    #     "index"=>0}]}

    response_text = chat_response.dig("choices", 0, "message", "content").strip
    logger.info "Chat Response Text: #{response_text}"
    response = Response.new(
      query: query,
      text: response_text,
      n_query_tokens: chat_response.dig("usage", "prompt_tokens"),
      n_response_tokens: chat_response.dig("usage", "completion_tokens"),
      body: chat_response,
      slack_thread_ts: message.slack_thread_ts
    )

    # TODO: make the following response creation into Response's instance method

    model = chat_response["model"]
    answer = "<@#{message.user.slack_id}> #{response.text}"
    post_params = SlackBot.format_chat_gpt_response(
      answer,
      prompt_tokens: response.n_query_tokens,
      completion_tokens: response.n_response_tokens,
      model: model
    )

    posted_message = Utils.post_message(
      channel: message.conversation.slack_id,
      thread_ts: message.slack_thread_ts,
      **post_params
    )
    logger.info posted_message.inspect

    unless posted_message.ok
      error_query(message)
      return
    end

    response.slack_ts = posted_message.ts
    response.slack_thread_ts = message.slack_thread_ts

    Query.transaction do
      query.save!
      response.save!
    end
  end

  private def start_query(message, name=REACTION_SYMBOL)
    start_response(message, name)
  end

  private def finish_query(message, name=REACTION_SYMBOL)
    finish_response(message, name)
  end

  private def error_query(message, name=ERROR_REACTION_SYMBOL)
    error_response(message, name)
  end
end
