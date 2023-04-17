module Utils
  module_function def chat_completion(*messages, model: nil, temperature: nil)
    params = {
      parameters: {
        model: model || "gpt-3.5-turbo",
        messages: messages,
        temperature: temperature || 0.7
      }
    }

    client = OpenAI::Client.new
    client.chat(**params)
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

    [{role: "user", content: content.strip}]
  end

  DEFAULT_PROMPT = <<~END_DEFAULT_PROMPT.chomp.freeze
    You are ChatGPT, a large language model trained by OpenAI.
    Answer as concisely as possible.
    Current date: {current_date}
  END_DEFAULT_PROMPT

  module_function def default_prompt
    Rails.application.credentials.default_prompt || DEFAULT_PROMPT
  end
end
