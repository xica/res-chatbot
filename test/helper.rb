ENV["APP_ENV"] = "test"
ENV["OPENAI_ACCESS_TOKEN"] = "test-openai"
ENV["SLACK_BOT_TOKEN"] = "test-slack-bot-token"

require "rack/test"
require "sidekiq/testing"
require "test/unit/rr"
require "webmock/test_unit"

require "slack_bot/app"

module TestHelper
  def decode_slack_client_request_body(request_body)
    body = URI.decode_www_form(request_body).to_h
    body.transform_values {|value| JSON.load(value) rescue value }
  end

  def api_usage_block(prompt_tokens, completion_tokens, model)
    total_tokens = prompt_tokens + completion_tokens
    prompt_amount_jpy = prompt_tokens * SlackBot.prompt_unit_price(model) * SlackBot::USDJPY
    completion_amount_jpy = completion_tokens * SlackBot.completion_unit_price(model) * SlackBot::USDJPY
    total_amount_jpy = prompt_amount_jpy + completion_amount_jpy
    {
      "type" => "context",
      "elements" => [
        {
          "type" => "mrkdwn",
          "text" => [
            "API Usage:",
            "total %d tokens \u{2248} \u{a5}%0.2f" % [total_tokens, total_amount_jpy],
            "(prompt + completion =",
            "%d + %d tokens \u{2248}" % [prompt_tokens, completion_tokens],
            "\u{a5}%0.2f + \u{a5}%0.2f)" % [prompt_amount_jpy, completion_amount_jpy],
          ].join(" ")
        }
      ]
    }
  end

  def feedback_action_block
    {
      "type" => "actions",
      "elements" => [
        {
          "type" => "button",
          "text" => {
            "type" => "plain_text",
            "emoji" => true,
            "text" => "Good"
          },
          "style" => "primary",
          "value" => "good"
        },
        {
          "type" => "button",
          "text" => {
            "type" => "plain_text",
            "emoji" => true,
            "text" => "Bad"
          },
          "style" => "danger",
          "value" => "bad"
        }
      ]
    }
  end
end
