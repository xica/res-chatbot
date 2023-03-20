class TestChatGPTJob < Test::Unit::TestCase
  sub_test_case("ChatGPTJob.perform") do
    def test_normal_case
      channel_id = "XXX"
      user_id = "YYY"
      query = "ZZZ"
      answer = "ABC"
      expected_response = "<@#{user_id}> #{answer}"

      stub_request(:post, "https://slack.com/api/chat.postMessage")

      assert_rr do
        mock(Utils).chat_completion(query) { {"choices" => [{"message" => {"content" => answer}}]} }
        Sidekiq::Testing.inline! do
          ChatGPTJob.perform_async({
            "channel" => channel_id,
            "user" => user_id,
            "message" => query
          })
        end
      end

      assert_requested(:post, "https://slack.com/api/chat.postMessage",
                       body: {"channel" => channel_id,
                              "text" => expected_response})
    end
  end
end
