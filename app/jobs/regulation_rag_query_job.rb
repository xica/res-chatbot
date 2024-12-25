class RegulationRagQueryJob < SlackRagJob
  queue_as :default

  DEFAULT_MODEL = "gpt-4o"
  DEFAULT_EMBEDDING_MODEL = "text-embedding-3-large"
  REGULATION_RAG_INDEX = "regulation-rag-index"
  EMBEDDING_DIMS = 512
  TEXT_FIELD = "content"
  EMBEDDING_FIELD = "embedding"


  def llm_model(message = nil)
    DEFAULT_MODEL
  end

  def embedding_model
    DEFAULT_EMBEDDING_MODEL
  end

  def embedding_dims
    EMBEDDING_DIMS
  end

  def regulation_rag_index
    REGULATION_RAG_INDEX
  end

  private def system_message
<<SYSTEM_MESSAGE
社内規定に関するクエリに対して、クエリに関連する情報を参照して回答を生成してください。
出力形式は指定のものとし、該当するの一覧を全て出力してください。

## 出力形式
質問に該当する可能性がある社内規定文書は以下のとおりです。

【以下の形式を必要な分だけ繰り返す】
{title} に関連する内容が記載されてるかもしれません。
詳細は以下のファイルをご確認ください。
- ファイル名: {file_name}
- 該当部分: {クエリに関連のある該当部分の記述}

## クエリに関連する情報
SYSTEM_MESSAGE
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

    options = nil

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
    llm_model = self.llm_model(message)

    query = Query.new(
      message: message,
      text: "[REGULATION RAG QUERY] #{message.text}",
      body: {
        parameters: {
          llm_model: llm_model,
          embedding_model: self.embedding_model
        }
      }
    )

    begin
      answer = generate_answer(message.text, llm_model)
      logger.info "Regulation RAG Answer length: #{answer.length}"
      logger.info "Regulation RAG Answer:\n" + answer.each_line.map {|l| "> #{l}" }.join("")
    rescue Exception => err
      error_response(message)
      Utils.post_message(
        channel: message.conversation.slack_id,
        thread_ts: message.slack_thread_ts,
        text: [
          ":bangbang: *ERROR*: " + err.inspect,
          err.full_message(highlight: false)
        ].join("\n"),
        mrkdwn: true
      )
      message.destroy
      return
    end

    response = Response.new(
      query: query,
      text: "[REGULATION RAG ANSWER] #{answer}",
      n_query_tokens: 0,
      n_response_tokens: 0,
      body: { "answer" => answer },
      slack_thread_ts: message.slack_thread_ts
    )

    # post_params = format_rag_response(
    #   answer,
    #   user: message.user
    # )

    post_params = format_simple_rag_response(
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
      message.destroy!  # TODO: remove this
      # query.save!
      # response.save!
    end
  end

  private def generate_answer(query, llm_model)
    relevant_text = generate_relevant_text(query)

    assistant_content = relevant_text.map{|hit| JSON.dump(hit) }.join("\n\n")

    response = Utils.chat_completion(
      {role: "system", content: self.system_message},
      {role: "user", content: query},
      {role: "assistant", "content": assistant_content},

      model: llm_model,
      temperature: 0,
      max_tokens: 3000,
      top_p: 1,
      frequency_penalty: 0,
      presence_penalty: 0,
    )

    logger.info "Chat completion response: #{response}"

    response.dig("choices", 0, "message", "content")
  end

  private def generate_relevant_text(query, embedding_field: EMBEDDING_FIELD, text_field: TEXT_FIELD)
    response = retrieve_documents(query, embedding_field: embedding_field)

    response.dig("hits", "hits").map do |hit|
      source = hit["_source"]
      node_id = hit["_id"]
      text = source[text_field]
      metadata = source["metadata"]
      logger.info "Relevant Text Metadata: #{metadata}"

      # TODO: Process this on indexing phase
      file_name, url = document_file_name_url(metadata["file_name"])

      node_info = source["node_info"]
      start_char_idx = node_info && node_info["start"]
      end_char_idx = node_info && node_info["end"]

      {
        text: text,
        start_char_idx: start_char_idx,
        end_char_idx: end_char_idx,
        metadata: {
          title: metadata["title"],
          file_name: file_name,
          # TODO: url: url
        }
      }.compact
    end
  end

  private def document_file_name_url(file_name)
    file_name = File.basename(file_name)
    file_name.gsub!(/\.md$/, ".pdf")
    file_name
  end

  private def retrieve_documents(query, k: 10, embedding_field: EMBEDDING_FIELD)
    query_embedding = calculate_embeddings(query)

    response = opensearch_client.search(
      index: regulation_rag_index,
      body: {
        size: k,
        query: {knn: {"#{embedding_field}": {vector: query_embedding, k: k}}}
      }
    )

    response
  end

  private def calculate_embeddings(txt)
    response = Utils.calculate_embeddings(txt, model: self.embedding_model, dims: self.embedding_dims)
    response.dig("data", 0, "embedding")
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

  private def opensearch_client
    @os_client ||= create_opensearch_client
  end

  private def create_opensearch_client
    credentials_provider = Aws::CredentialProviderChain.new.resolve

    signer = Aws::Sigv4::Signer.new(
      service: "es",
      region: OPENSEARCH_AWS_REGION,
      credentials_provider: credentials_provider
    )

    OpenSearch::Aws::Sigv4Client.new({
      host: OPENSEARCH_ENDPOINT,
      request_timeout: 30,
      retry_on_failure: 5,
      transport_options: { ssl: { verify: true } },
    }, signer)
  end
end
