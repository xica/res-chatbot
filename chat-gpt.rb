require "openai"

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_ACCESS_TOKEN")

  org_id = ENV.fetch("OPENAI_ORGANIZATION_ID", nil)
  config.organization_id = org_id if org_id
end

module ChatGPT
  module_function def chat_completion(message)
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    response.dig("choices", 0, "message", "content")
  end
end
