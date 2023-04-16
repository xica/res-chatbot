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
    content = <<~END_MESSAGE
    #{prompt}

    {query_body}
    END_MESSAGE

    content.gsub!('{current_date}', Time.now.strftime("%Y-%m-%d"))
    content.gsub!('{query_body}', query_body)

    [{role: "user", content: content.strip}]
  end
end
