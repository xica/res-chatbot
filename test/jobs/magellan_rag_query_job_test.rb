require "test_helper"

class MagellanRagQueryJobOptionsTest < ActiveSupport::TestCase
  test "creation without any options" do
    options = MagellanRagQueryJob::Options.new
    assert_equal("gpt-4o",
                 options.model)
    assert_nil options.validate!
  end

  test "creation from a hash" do
    skip
  end
end

class MagellanRagQueryJobTest < ActiveSupport::TestCase
  include SlackTestHelper

  test "normal case" do
    message = messages(:report_query_one)
    channel = message.conversation
    user = message.user
    answer = "DUMMY RAG ANSWER"
    expected_response = "<@#{user.slack_id}> #{answer}"

    mock(Utils::MagellanRAG).generate_answer(message.text) do
      {"answer" => answer}
    end

    stub_slack_api(:post, "chat.postMessage").to_return(body: {ok: true, ts: Time.now.to_f.to_s}.to_json)
    stub_slack_api(:post, "reactions.add")
    stub_slack_api(:post, "reactions.remove")

    MagellanRagQueryJob.perform_now("message_id" => message.id)

    actual_body = nil
    assert_slack_api_called(:post, "chat.postMessage") do |request|
      actual_body = decode_slack_client_request_body(request.body)
    end

    assert_slack_api_called(:post, "reactions.add",
                            body: {
                              "channel" => channel.slack_id,
                              "timestamp" => message.slack_ts,
                              "name" => "hourglass_flowing_sand"
                            })

    assert_slack_api_called(:post, "reactions.remove",
                            body: {
                              "channel" => channel.slack_id,
                              "timestamp" => message.slack_ts,
                              "name" => "hourglass_flowing_sand"
                            })

    assert_equal(
      {
        "channel" => channel.slack_id,
        "text" => expected_response,
        "blocks" => [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => expected_response,
            },
          },
          feedback_action_block
        ],
        "thread_ts" => message.slack_thread_ts
      },
      actual_body
    )
  end
end
