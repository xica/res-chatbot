ENV["APP_ENV"] = "test"
ENV["OPENAI_ACCESS_TOKEN"] = "test-openai"
ENV["SLACK_BOT_TOKEN"] = "test-slack-bot-token"

require "rack/test"
require "sidekiq/testing"
require "test/unit/rr"
require "webmock/test_unit"

require "app"
require "job"
