ENV["RAILS_ENV"] ||= "test"
ENV["APP_ENV"] ||= "test"
ENV["OPENAI_ACCESS_TOKEN"] = "test-openai"
ENV["SLACK_BOT_TOKEN"] = "test-slack-bot-token"
ENV["SLACK_SIGNING_SECRET"] = "3d3dbfb61ac7935eefb4b4d8f5aaf930"

require_relative "../config/environment"
require "database_rewinder"
require "openssl"
require "pathname"
require "rails/test_help"
require "rr"
require "sidekiq/testing"
require "webmock/minitest"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures %w(
    users
    conversations
    memberships
    messages
    queries
    responses
  )

  def fixture_file_path(relpath)
    Pathname(__FILE__).parent.join("fixtures", "files", relpath)
  end

  # Add more helper methods to be used by all tests here...
  module DatabaseRewinderSupport
    def before_setup
      super
      DatabaseRewinder.start
    end

    def after_teardown
      DatabaseRewinder.clean
      super
    end
  end

  include DatabaseRewinderSupport

  module SlackTestHelper
    def stub_slack_api(http_method, api_method, body: nil, headers: nil)
      url = File.join(Slack::Web.config.endpoint, api_method)

      with_params = {}
      with_params[:body] = body if body
      with_params[:headers] = headers || {}
      with_params[:headers]["Content-Type"] ||= "application/x-www-form-urlencoded"

      stub_request(http_method, url).with(**with_params)
    end

    def assert_slack_api_called(http_method, api_method, **params, &block)
      params[:headers] ||= {}
      params[:headers]["Content-Type"] ||= "application/x-www-form-urlencoded"
      url = File.join(Slack::Web.config.endpoint, api_method)
      assert_requested(http_method, url, **params, &block)
    end

    def decode_slack_client_request_body(request_body)
      body = URI.decode_www_form(request_body).to_h
      body.map { |key, value|
        value = case key
                when "ts", "thread_ts"
                  value
                else
                  JSON.load(value) rescue value
                end
        [key, value]
      }.to_h
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

    def compute_request_signature(timestamp, body, version="v0")
      secret = ENV["SLACK_SIGNING_SECRET"]

      signature_basestring = [version, timestamp, body].join(":")
      hex_digest = OpenSSL::HMAC.hexdigest("sha256", secret, signature_basestring)
      [version, hex_digest].join("=")
    end

    def with_env(new_env)
      save = ENV.to_hash
      ENV.update(new_env)
      yield
    ensure
      ENV.replace(save)
    end
  end

  module OnAzureOpenAIService
    def setup
      super
      @saved_configuration = OpenAI.configuration
      OpenAI.configuration = OpenAI.configuration.dup

      OpenAI.configuration.api_type = :azure
      OpenAI.configuration.uri_base = "https://test.openai.azure.com/openai/deployments/test-gpt35turbo-001"
      OpenAI.configuration.api_version = "2023-03-15-preview"
    end

    def teardown
      super
      OpenAI.configuration = @saved_configuration
    end
  end

  unless defined? ActiveSupport::Testing::ConstantStubbing
    module ConstantStubbing
      def stub_const(mod, constant, new_value)
        old_value = mod.const_get(constant, false)
        mod.send(:remove_const, constant)
        mod.const_set(constant, new_value)
        yield
      ensure
        mod.send(:remove_const, constant)
        mod.const_set(constant, old_value)
      end
    end

    include ConstantStubbing
  end
end
