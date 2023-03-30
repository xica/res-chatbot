require "test_helper"
require "utils"

class UtilsTest < ActiveSupport::TestCase
  test "chat_completion" do
    stub_request(:post, "https://api.openai.com/v1/chat/completions")

    Utils.chat_completion(
      { role: "user", content: "Hello ChatGPT" },
      model: "gpt-3.5-turbo",
      temperature: 0.8
    )

    assert_requested(
      :post, "https://api.openai.com/v1/chat/completions",
      body: {
        "model" => "gpt-3.5-turbo",
        "messages" => [
          { role: "user", content: "Hello ChatGPT" },
        ],
        "temperature" => 0.8
      }
    )
  end
end
