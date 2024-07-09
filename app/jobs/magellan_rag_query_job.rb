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
    :retrieval_only,
    keyword_init: true
  ) do
    def initialize(**kw)
      super
      self.model ||= DEFAULT_MODEL
      self.retrieval_only = false if self.retrieval_only.nil?
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
    logger.error "ERROR: #{error.message}\n#{error.backtrace.join("\n")}"
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

    if options.retrieval_only
      documents = Utils::MagellanRAG.retrieve_documents(message.text)
      rag_response = format_relevant_documents(documents)
    else
      rag_response = Utils::MagellanRAG.generate_answer(message.text)
    end
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
    logger.info "RAG Answer length: #{answer.length}"
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

    begin
      posted_message = Utils.post_message(
        channel: message.conversation.slack_id,
        thread_ts: message.slack_thread_ts,
        **post_params
      )
    rescue Exception => err
      logger.warn "Error occurred on post_message: #{err.full_message(highlight: false)}"

      post_params = format_simple_rag_response(
        answer,
        user: message.user
      )

      posted_message = Utils.post_message(
        channel: message.conversation.slack_id,
        thread_ts: message.slack_thread_ts,
        **post_params
      )
    end
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

  private def format_relevant_documents(documents)
    logger.info "[format_relevant_documents] documents=#{documents.inspect}"
    s = documents.map.with_index {|doc, i|
      company_name = doc.dig("metadata", "company_name")
      file_name = doc.dig("metadata", "file_name")
      file_url = doc.dig("metadata", "file_url")
      content = doc["content"]

      header = "# Doc-#{i}"
      header << ": #{company_name}" if company_name

      file_name = file_name ? "* file_name = #{file_name}\n" : ""
      file_url = file_url ? "* file_url = #{file_url}\n" : ""

      <<~END_FORMAT
      #{header}
      #{file_name}#{file_url}#{content}
      END_FORMAT
    }.join("\n\n")
    {"answer" => s}
  end

  private def format_simple_rag_response(answer, user:)
    answer = rewrite_markdown_link(answer)
    text = "<@#{user.slack_id}> 回答は次のとおりです。\n\n#{answer}"
    response = SlackBot.format_chat_gpt_response(text)
    feedback_block = response[:blocks].pop
    response[:blocks] << { "type": "divider" }
    response[:blocks] << feedback_block
    response
  end

  private def rewrite_markdown_link(s)
    s.gsub(/\[(.+?)\]\((.+?)\)/) { "<#{$2}|#{$1}>" }
  end

  private def format_rag_response(answer, user:)
    answer_blocks = format_answer_blocks(answer, user)
    text = "#{answer_blocks[0][:text][:text]}\n\n#{answer}"
    response = SlackBot.format_chat_gpt_response(text)
    response[:blocks][0,1] = answer_blocks
    response
  end

  private def format_answer_blocks(answer, user)
    kases = Utils::MagellanRAG.parse_answer(answer)
    blocks = [
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "<@#{user.slack_id}> 次の#{kases.length}件の文書が質問に該当する可能性があります。"
        }
      }
    ]
    kases.each do |kase|
      blocks << format_kase(kase)
      blocks << {"type": "divider"}
    end
    blocks
  end

  private def format_kase(kase)
    {
      "type": "rich_text",
      "elements": [
        {
          "type": "rich_text_section",
          "elements": [
            "type": "text",
            "text": kase.description
          ]
        },
        {
          "type": "rich_text_list",
          "style": "bullet",
          "indent": 0,
          "elements": [
            {
              "type": "rich_text_section",
              "elements": [
                {
                  "type": "text",
                  "text": "ファイル: "
                },
                {
                  "type": "link",
                  "url": kase.file_url,
                  "text": kase.file_name
                }
              ]
            },
            {
              "type": "rich_text_section",
              "elements": [
                {
                  "type": "text",
                  "text": "該当部分: #{kase.matching_part}"
                }
              ]
            }
          ]
        }
      ],
    }
  end
end
