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

  sub_test_case("POST /slack/commands/translate/:lang") do
    test("case of known lang") do
      channel_id = "XXX"
      user_id = "YYY"
      query_body = <<~END_QUERY
        Input sentence 1
        Input sentence 2
      END_QUERY
      answer = <<~END_ANSWER
        [LANG]
        English

        [Translation]
        Output sentence 1
        Output sentence 2
        Output sentence 3

        [LANG]
        Japanese

        [Translation]
        Output sentence 4
        Output sentence 5
        Output sentence 6
      END_ANSWER

      expected_response = <<~END_RESPONSE
        <@#{user_id}>
        Original (English):
        > Input sentence 1
        > Input sentence 2

        Japanese Translation:
        > Output sentence 1
        > Output sentence 2
        > Output sentence 3
      END_RESPONSE

      query = TranslateJob.send(:format_query, "ja", query_body)
      stub(ChatGPT).chat_completion(query) { answer }
      stub_request(:post, "https://slack.com/api/chat.postMessage")

      Sidekiq::Testing.inline! do
        post("/slack/commands/translate/ja",
             {
               text: query_body,
               channel_id: channel_id,
               user_id: user_id,
               lang: "ja"
             })
      end

      assert last_response.ok?

      assert_requested(:post, "https://slack.com/api/chat.postMessage",
                       body: {"channel" => channel_id,
                              "text" => expected_response})
    end

    test("case of unknown lang") do
      channel_id = "XXX"
      user_id = "YYY"
      query_body = <<~END_QUERY
        Input sentence 1
        Input sentence 2
      END_QUERY

      stub_request(:post, "https://slack.com/api/chat.postMessage")

      Sidekiq::Testing.inline! do
        post("/slack/commands/translate/unknownlang",
             {
               text: query_body,
               channel_id: channel_id,
               user_id: user_id,
               lang: "unknownlang"
             })
      end

      assert last_response.ok?
      assert_equal(last_response.body,
                   "ERROR: Unsupported language code `unknownlang`")

      assert_not_requested(:post, "https://slack.com/api/chat.postMessage")
    end
  end
end
