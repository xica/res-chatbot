module Utils
  module_function def chat_completion(message, model: nil, temperature: nil)
    client = OpenAI::Client.new
    client.chat(
      parameters: {
        model: model || "gpt-3.5-turbo",
        messages: [
          { role: "user", content: message }
        ],
        temperature: temperature || 0.7
      }
    )
  end

  module_function def post_message(channel:, text:)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: text)
  end
end
