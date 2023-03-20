module Utils
  module_function def chat_completion(*messages, model: nil, temperature: nil)
    client = OpenAI::Client.new
    client.chat(
      parameters: {
        model: model || "gpt-3.5-turbo",
        messages: messages,
        temperature: temperature || 0.7
      }
    )
  end

  module_function def post_message(channel:, **params)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, **params)
  end
end
