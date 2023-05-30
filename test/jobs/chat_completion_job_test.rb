require "test_helper"

class ChatCompletionJobOptionsTest < ActiveSupport::TestCase
  test "creation from a hash" do
    hash_options = {
      "model" => "gpt-3.5-turbo",
      "temperature" => 1.5,
      "top_p" => 0.5,
      "no_default_prompt" => true
    }
    options = ChatCompletionJob::Options.new(**hash_options)
    assert_equal ["gpt-3.5-turbo", 1.5, 0.5, true],
                 [options.model, options.temperature, options.top_p, options.no_default_prompt]
  end

  test "validate_model!" do
    assert_nothing_raised do
      ChatCompletionJob::Options.new("model" => "gpt-3.5-turbo").validate_model!
    end

    assert_nothing_raised do
      ChatCompletionJob::Options.new("model" => "gpt-4").validate_model!
    end

    assert_nothing_raised do
      ChatCompletionJob::Options.new("model" => "xxx-gpt-35-turbo-456").validate_model!
    end
  end
end


class ChatCompletionJobTest < ActiveJob::TestCase
  include SlackTestHelper

  test "normal case" do
    message = messages(:one)
    channel = message.conversation
    user = message.user
    answer = "ABC"
    expected_response = "<@#{user.slack_id}> #{answer}"

    mock(Utils).chat_completion(
      {
        "role" => "user",
        "content" => <<~END_CONTENT.chomp
          You are ChatGPT, a large language model trained by OpenAI.
          Answer as concisely as possible.
          Current date: #{Time.now.strftime("%Y-%m-%d")}

          #{message.text}
        END_CONTENT
      },
      model: "gpt-3.5-turbo",
      temperature: 0.7
    ) do
      {
        "model" => "gpt-3.5-turbo-0301",
        "usage" => {
          "prompt_tokens" => 70,
          "completion_tokens" => 50,
          "total_tokens" => 120
        },
        "choices" => [
          {
            "message" => {"content" => answer}
          }
        ]
      }
    end

    stub_slack_api(:post, "chat.postMessage").to_return(body: {ok: true, ts: Time.now.to_f.to_s}.to_json)
    stub_slack_api(:post, "reactions.add")
    stub_slack_api(:post, "reactions.remove")

    ChatCompletionJob.perform_now("message_id" => message.id)

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
              "text" => expected_response
            }
          },
          api_usage_block(70, 50, "gpt-3.5-turbo-0301"),
          feedback_action_block
        ],
        "thread_ts" => message.slack_thread_ts
      },
      actual_body
    )
  end


  test "duplicate case" do
    message = messages(:two)

    dont_allow(Utils).chat_completion

    ChatCompletionJob.perform_now("message_id" => message.id)
  end


  test "for a message in gpt-4 allowed conversation" do
    message = messages(:one)
    channel = message.conversation
    user = message.user
    answer = "ABC"
    expected_response = "<@#{user.slack_id}> #{answer}"

    channel.update!(model: "gpt-4")

    mock(Utils).chat_completion(
      {
        "role" => "user",
        "content" => <<~END_CONTENT.chomp
          You are ChatGPT, a large language model trained by OpenAI.
          Answer as concisely as possible.
          Current date: #{Time.now.strftime("%Y-%m-%d")}

          #{message.text}
        END_CONTENT
      },
      model: "gpt-4",
      temperature: 0.7
    ) do
      {
        "model" => "gpt-4-0314",
        "usage" => {
          "prompt_tokens" => 70,
          "completion_tokens" => 50,
          "total_tokens" => 120
        },
        "choices" => [
          {
            "message" => {"content" => answer}
          }
        ]
      }
    end

    stub_slack_api(:post, "chat.postMessage").to_return(body: {ok: true, ts: Time.now.to_f.to_s}.to_json)
    stub_slack_api(:post, "reactions.add")
    stub_slack_api(:post, "reactions.remove")

    ChatCompletionJob.perform_now("message_id" => message.id)

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
              "text" => expected_response
            }
          },
          api_usage_block(70, 50, "gpt-4-0314"),
          feedback_action_block
        ],
        "thread_ts" => message.slack_thread_ts
      },
      actual_body
    )
  end


  class WithNonNilRailsApplicationCredentialsDefaultPromptTest < ActiveJob::TestCase
    include SlackTestHelper

    def teardown
      Rails.application.credentials.default_prompt = nil
    end

    test "with non-nil Rails.application.credentials.default_prompt" do
      Rails.application.credentials.default_prompt = <<~END_DEFAULT_PROMPT
        Before query_body

        {query_body}

        After query_body
      END_DEFAULT_PROMPT

      message = messages(:one)
      channel = message.conversation
      user = message.user
      answer = "ABC"
      expected_response = "<@#{user.slack_id}> #{answer}"

      mock(Utils).chat_completion(
        {
          "role" => "user",
          "content" => <<~END_CONTENT.chomp
            Before query_body

            #{message.text}

            After query_body
          END_CONTENT
        },
        model: "gpt-3.5-turbo",
        temperature: 0.7
      ) do
        {
          "model" => "gpt-3.5-turbo-0301",
          "usage" => {
            "prompt_tokens" => 70,
            "completion_tokens" => 50,
            "total_tokens" => 120
          },
          "choices" => [
            {
              "message" => {"content" => answer}
            }
          ]
        }
      end

      stub_slack_api(:post, "chat.postMessage").to_return(body: {ok: true, ts: Time.now.to_f.to_s}.to_json)
      stub_slack_api(:post, "reactions.add")
      stub_slack_api(:post, "reactions.remove")

      ChatCompletionJob.perform_now("message_id" => message.id)

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
                "text" => expected_response
              }
            },
            api_usage_block(70, 50, "gpt-3.5-turbo-0301"),
            feedback_action_block
          ],
          "thread_ts" => message.slack_thread_ts
        },
        actual_body
      )
    end
  end
end
