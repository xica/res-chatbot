require "slack_bot/utils"
require "utils"

class MagellanRagQueryJob < SlackResponseJob
  queue_as :default

  VALID_MODELS = [
    # OpenAI API
    "gpt-4o".freeze,
  ]

  DEFAULT_MODEL = ENV.fetch("MAGELLAN_RAG_DEFAULT_MODEL", VALID_MODELS[0])

  class InvalidOptionError < StandardError; end

  Options = Struct.new(
    :model,
    keyword_init: true
  ) do
    def initialize(**kw)
      super
      self.model ||= DEFAULT_MODEL
    end

    def validate!
      validate_model! unless model.nil?
    end

    def validate_model!
      MagellanRagQueryJob::VALID_MODELS.each do |valid_model|
        case valid_model
        when Regexp
          return if valid_model.match?(model)
        else
          return if model == valid_model
        end
      end
      raise InvalidOptionError, "Invalid model is specified: #{model}"
    end
  end

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
      start_response(message)
      process_query(message, options)
    ensure
      finish_response(message)
    end
  rescue Exception => error
    logger.error "ERROR: #{error.message}"
    raise unless Rails.env.production?
  end

  private def process_query(message, options)
    if message.slack_ts != message.slack_thread_ts
      # NOTE: This job currently does not support queries in threads.
      error_response("スレッドでの問い合わせには対応していません。")
      return
    end

    model = options.model
    query = Query.new(
      message: message,
      text: "[RAG QUERY] #{message.text}",
      body: {
        parameters: {
          model: model
        }
      }
    )

    rag_response = Utils::MagellanRAG.generate_answer(message.text)
    logger.info "RAG Response:\n" + rag_response.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")

    unless rag_response.key? "answer"
      Util.post_message(
        channel: message.conversation.slack_id,
        thread_ts: message.slack_thread_ts,
        text: ":#{ERROR_REACTION_SYMBOL}: *ERROR*: No answer key in the response from RAG: #{rag_response.inspect}",
        mrkdwn: true
      )
      error_response(message)
      return
    end

    answer = rag_response["answer"]
    logger.info "RAG Answer:\n" + answer.each_line.map {|l| "> #{l}" }.join("")

    response = Response.new(
      query: query,
      text: "[RAG ANSWER] #{answer}",
      n_query_tokens: 0,
      n_response_tokens: 0,
      body: rag_response,
      slack_thread_ts: message.slack_thread_ts
    )

    post_params = format_rag_response(
      answer,
      user: message.user
    )

    posted_message = Utils.post_message(
      channel: message.conversation.slack_id,
      thread_ts: message.slack_thread_ts,
      **post_params
    )
    logger.info posted_message.inspect

    unless posted_message.ok
      error_response(message)
      return
    end

    response.slack_ts = posted_message.ts
    response.slack_thread_ts = message.slack_thread_ts

    Query.transaction do
      query.save!
      response.save!
    end
  end

  private def format_rag_response(answer, user:)
    text = "<@#{user.slack_id}> #{answer}"
    SlackBot.format_chat_gpt_response(text)
  end
end
