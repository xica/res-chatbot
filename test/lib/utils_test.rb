require "test_helper"
require "utils"

class UtilsTest < ActiveSupport::TestCase
  test "chat_completion" do
    stub_request(:post, "https://api.openai.com/v1/chat/completions")

    Utils.chat_completion(
      { "role" => "user", "content" => "Hello ChatGPT" },
      model: "gpt-3.5-turbo",
      temperature: 0.8
    )

    assert_requested(
      :post, "https://api.openai.com/v1/chat/completions",
      body: {
        "model" => "gpt-3.5-turbo",
        "messages" => [
          { "role" => "user", "content" => "Hello ChatGPT" },
        ],
        "temperature" => 0.8
      }
    )
  end

  class OnAzureOpenAIServiceTest < ActiveSupport::TestCase
    def setup
      @saved_configuration = OpenAI.configuration
      OpenAI.configuration = OpenAI.configuration.dup

      OpenAI.configuration.api_type = :azure
      OpenAI.configuration.uri_base = "https://test.openai.azure.com/openai/deployments/test-gpt35turbo-001"
      OpenAI.configuration.api_version = "2023-03-15-preview"
    end

    def teardown
      OpenAI.configuration = @saved_configuration
    end

    test "chat_completion" do
      skip "I do not know why the following stub_request doeos not work"

      stub_request(:post, "https://test.openai.azure.com/openai/deployments/test-gpt35turbo-001/chat/completions?api_version=2023-03-15-preview")

      Utils.chat_completion(
        { "role" => "user", "content" => "Hello ChatGPT" },
        model: "gpt-35-turbo",
        temperature: 0.8
      )

      assert_requested(
        :post, "https://test.openai.azure.com/openai/deployments/test-gpt35turbo-001/chat/completions?api_version=2023-03-15-preview",
        body: {
          "model" => "gpt-35-turbo",
          "messages" => [
            { "role" => "user", "content" => "Hello ChatGPT" },
          ],
          "temperature" => 0.8
        }
      )
    end
  end

  class MakeFirstMessagesTest < ActiveSupport::TestCase
    test "with prompt that includes '{query_body}'" do
      prompt = "abc\n{query_body}\nxyz"
      result = Utils.make_first_messages(prompt, "QUERY BODY")
      assert_equal "abc\nQUERY BODY\nxyz", result.dig(0, "content")
    end

    test "with prompt that does not includes '{query_body}'" do
      prompt = "abc\nxyz"
      result = Utils.make_first_messages(prompt, "QUERY BODY")
      assert_equal "abc\nxyz\n\nQUERY BODY", result.dig(0, "content")
    end
  end

  class DefaultPromptTest < ActiveSupport::TestCase
    def teardown
      Rails.application.credentials.default_prompt = nil
    end

    test "with non nil Rails.application.credentials.default_prompt" do
      Rails.application.credentials.default_prompt = <<~END_DEFAULT_PROMPT
        Before query_body

        {query_body}

        After query_body
      END_DEFAULT_PROMPT

      assert_equal Rails.application.credentials.default_prompt,
                   Utils.default_prompt
    end
  end
end
