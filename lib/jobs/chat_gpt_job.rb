require "sidekiq"
require "utils"

class ChatGPTJob
  include Sidekiq::Job

  def perform(params)
    channel = params["channel"]
    user = params["user"]
    message = params["message"]

    response = Utils.chat_completion(message)
    response_content = response.dig("choices", 0, "message", "content")
    answer = "<@#{user}> #{response_content}"

    Utils.post_message(channel: channel, text: answer)
  end
end
