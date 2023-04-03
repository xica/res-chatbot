require "test_helper"
require "utils"

class SlackInteractionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  test "good feedback" do
    channel = conversations(:random)
    user = users(:one)
    message = messages(:three)

    payload = {
      type: "block_actions",
      message: {
        text: message.query.response.text,
        ts: message.query.response.slack_ts,
        blocks: [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => message.query.response.text
            }
          },
          api_usage_block(70, 50, "gpt-3.5-turbo-0301"),
          feedback_action_block
        ]
      },
      response_url: "https://response.example.com/XXXX/YYYY/ZZZZ",
      actions: [
        { value: "good" }
      ]
    }

    stub_request(:post, payload[:response_url])

    params = {payload: payload.to_json}
    request_body = URI.encode_www_form(params)
    timestamp = Time.now.to_i
    headers = {
      "X-Slack-Request-Timestamp": timestamp,
      "X-Slack-Signature": compute_request_signature(timestamp, request_body)
    }

    post "/slack/interactions", params:, headers: headers

    expected_body = {
      text: payload.dig(:message, :text),
      blocks: payload.dig(:message, :blocks)
    }
    expected_body[:blocks] << {
      "type" => "context",
      "elements" => [
        {
          "type" => "mrkdwn",
          "text" => "Good feedback received."
        }
      ]
    }

    assert_requested :post, payload[:response_url], body: expected_body

    assert_equal true, Response.find(message.query.response.id).good
  end


  test "bad feedback" do
    channel = conversations(:random)
    user = users(:one)
    message = messages(:three)

    payload = {
      type: "block_actions",
      message: {
        text: message.query.response.text,
        ts: message.query.response.slack_ts,
        blocks: [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => message.query.response.text
            }
          },
          api_usage_block(70, 50, "gpt-3.5-turbo-0301"),
          feedback_action_block
        ]
      },
      response_url: "https://response.example.com/XXXX/YYYY/ZZZZ",
      actions: [
        { value: "bad" }
      ]
    }

    stub_request(:post, payload[:response_url])

    params = {payload: payload.to_json}
    request_body = URI.encode_www_form(params)
    timestamp = Time.now.to_i
    headers = {
      "X-Slack-Request-Timestamp": timestamp,
      "X-Slack-Signature": compute_request_signature(timestamp, request_body)
    }

    post "/slack/interactions", params:, headers: headers

    expected_body = {
      text: payload.dig(:message, :text),
      blocks: payload.dig(:message, :blocks)
    }
    expected_body[:blocks] << {
      "type" => "context",
      "elements" => [
        {
          "type" => "mrkdwn",
          "text" => "Bad feedback received."
        }
      ]
    }

    assert_requested :post, payload[:response_url], body: expected_body

    assert_equal false, Response.find(message.query.response.id).good
  end
end
