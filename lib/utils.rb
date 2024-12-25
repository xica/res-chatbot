module Utils
  module_function def chat_completion(*messages,
                                      model: nil,
                                      temperature: nil,
                                      max_tokens: nil,
                                      top_p: nil,
                                      frequency_penalty: nil,
                                      presence_penalty: nil
                                     )
    params = {
      model: model || "gpt-3.5-turbo",
      messages: messages,
      temperature: temperature || 0.7
    }

    params[:max_tokens] = max_tokens unless max_tokens.nil?
    params[:top_p] = top_p unless top_p.nil?
    params[:frequency_penalty] = frequency_penalty unless frequency_penalty.nil?
    params[:presence_penalty] = presence_penalty unless presence_penalty.nil?

    client = OpenAI::Client.new
    client.chat(parameters: params)
  end

  module_function def calculate_embeddings(input, model:, dims:)
    client = OpenAI::Client.new
    client.embeddings(parameters: {
      model: model,
      dimensions: dims,
      input: input
    })
  end

  module_function def post_message(channel:, text:, **params)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: text, **params)
  end

  module_function def post_ephemeral(channel:, user:, text:, **params)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postEphemeral(channel: channel, user: user, text: text, **params)
  end

  DEFAULT_MODEL = "gpt-3.5-turbo".freeze

  module_function def make_first_messages(prompt, query_body, model: DEFAULT_MODEL)
    content = if prompt.include?("{query_body}")
                prompt.dup
              else
                "#{prompt.chomp}\n\n{query_body}"
              end
    content.gsub!('{query_body}', query_body)
    content.gsub!('{current_date}', Time.now.strftime("%Y-%m-%d"))

    [{"role" => "user", "content" => content.strip}]
  end

  DEFAULT_PROMPT = <<~END_DEFAULT_PROMPT.chomp.freeze
    You are ChatGPT, a large language model trained by OpenAI.
    Answer as concisely as possible.
    Current date: {current_date}
  END_DEFAULT_PROMPT

  module_function def default_prompt
    Rails.application.credentials.default_prompt || DEFAULT_PROMPT
  end

  module_function def make_thread_context(message)
    prev_message = message.previous_message
    prev_query = prev_message.query
    if prev_query.blank?
      # TODO: internal error
    end

    prev_response = prev_query.response
    if prev_response.blank?
      # TODO: internal error
    end

    messages =  prev_query.body.dig("parameters", "messages").dup
    messages << prev_response.body.dig("choices", 0, "message")
    messages << {"role" => "user", "content" => message.text}
    messages
  end
end

require_relative "utils/magellan_rag"
