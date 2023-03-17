class TestApplication < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  sub_test_case("POST /slack/events") do
    sub_test_case("app_mention") do
      test("correctly mentioned at the beginning of the message") do
        channel_id = "XXX"
        user_id = "YYY"
        query_body = "ZZZ"
        query = "<@TEST_BOT_ID> #{query_body}"
        answer = "ABC"
        expected_response = "<@#{user_id}> #{answer}"

        stub(ChatGPT).chat_completion(query_body) { answer }
        stub_request(:post, "https://slack.com/api/chat.postMessage")

        Sidekiq::Testing.inline! do
          post("/slack/events",
               {
                 type: "event_callback",
                 event: {
                   type: "app_mention",
                   text: query,
                   channel: channel_id,
                   user: user_id
                 }
               }.to_json,
               "CONTENT_TYPE" => "application/json")
        end

        assert last_response.ok?
        assert_requested(:post, "https://slack.com/api/chat.postMessage",
                         body: {"channel" => channel_id,
                                "text" => expected_response})
      end
    end
  end
end
