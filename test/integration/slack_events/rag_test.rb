require "test_helper"
require "utils"

class SlackEventsRagTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  test "app_mention event from a channel for Magellan RAG" do
    slack_ts = Time.now.to_f.to_s
    channel = conversations(:magellan_rag)
    user = users(:one)
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"

    any_instance_of(SlackBot::Application) do |klass|
      stub(klass).magellan_rag_channel? do |ch|
        ch.slack_id == channel.slack_id
      end
    end

    stub_slack_api(:post, "chat.postMessage").to_return(body: { "ok" => true, "ts" => Time.now.to_f.to_s }.to_json)

    # Check the case when missing reactions:write scope
    stub_slack_api(:post, "reactions.add").to_return { raise Slack::Web::Api::Errors::MissingScope, "missing_scope" }
    stub_slack_api(:post, "reactions.remove").to_return { raise Slack::Web::Api::Errors::MissingScope, "missing_scope" }

    assert Message.find_by(conversation: channel, user: user, slack_ts: slack_ts).blank?

    assert_enqueued_with(job: MagellanRagQueryJob) do
      params = {
        type: "event_callback",
        event: {
          type: "app_mention",
          text: query,
          channel: channel.slack_id,
          user: user.slack_id,
          ts: slack_ts
        }
      }
      request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
      timestamp = slack_ts.to_i
      headers = {
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": compute_request_signature(timestamp, request_body)
      }

      post "/slack/events", params:, headers:, as: :json
    end

    message = Message.find_by!(conversation: channel, user: user, slack_ts: slack_ts)
    assert_equal([
                   query_body,
                   slack_ts,
                 ],
                 [
                   message.text,
                   message.slack_thread_ts,
                 ])

    mock(Utils::MagellanRAG).endpoint do
      "http://report-rag-api.test"
    end

    rag_answer = <<~END_ANSWER
      花王株式会社_エッセンシャルの事例では、TVCMの残存週が他社（11週）と比べて13週と長いと報告されています。
      詳細は以下のファイルで確認できます。
      - ファイル名: 【花王様】エッセンシャル_初回レポート報告_20221125.pdf
      - ファイルのURL: [こちら](https://drive.google.com/file/d/1MB_IerrxHZ_Dn3ziT7vPixaOF_ng84D3/preview?authuser=0)
      - 該当部分: 「15秒・30秒・60秒ともに他施策と比べて効率は良好。残存週は他社（11週）と比べて、13週と長い。」

      花王株式会社_ブランド横断の事例では、TVCMの残存週が業界傾向値（11週）と比べて13週と長いと報告されています。
      詳細は以下のファイルで確認できます。
      - ファイル名: 【花王様】横断レポート_20230116.pdf
      - ファイルのURL: [こちら](https://drive.google.com/file/d/1_t9ldOf-KcHxtC2fUS3sqCEJm8HwxMmU/preview?authuser=0)
      - 該当部分: 「残存週は業界傾向値（11週）と比べて、13週と長い。」
    END_ANSWER
    rag_response = {"answer": rag_answer}

    stub_request(
      :get, "http://report-rag-api.test/generate_answer"
    ).with(
      query: {"query" => "ZZZ"}
    ).to_return_json(
      status: 200,
      body: rag_response
    )

    expected_answer = rag_answer
    expected_response = "<@#{user.slack_id}> 次の2件の文書が質問に該当する可能性があります。\n\n#{expected_answer}"
    expected_answer_blocks = [
      {
        "type" => "section",
        "text" => {
          "type" => "mrkdwn",
          "text" => "<@#{user.slack_id}> 次の2件の文書が質問に該当する可能性があります。"
        }
      },
      {
        "type" => "rich_text",
        "elements" => [
          {
            "type" => "rich_text_section",
            "elements" => [
              "type" => "text",
              "text" => "花王株式会社_エッセンシャルの事例では、TVCMの残存週が他社（11週）と比べて13週と長いと報告されています。\n詳細は以下のファイルで確認できます。"
            ]
          },
          {
            "type" => "rich_text_list",
            "style" => "bullet",
            "indent" => 0,
            "elements" => [
              {
                "type" => "rich_text_section",
                "elements" => [
                  {"type" => "text", "text" => "ファイル: "},
                  {
                    "type" => "link",
                    "url" => "https://drive.google.com/file/d/1MB_IerrxHZ_Dn3ziT7vPixaOF_ng84D3/preview?authuser=0",
                    "text" => "【花王様】エッセンシャル_初回レポート報告_20221125.pdf"
                  }
                ]
              },
              {
                "type" => "rich_text_section",
                "elements" => [
                  {
                    "type" => "text",
                    "text" => "該当部分: 「15秒・30秒・60秒ともに他施策と比べて効率は良好。残存週は他社（11週）と比べて、13週と長い。」"
                  }
                ]
              }
            ]
          }
        ]
      },
      {"type" => "divider"},
      {
        "type" => "rich_text",
        "elements" => [
          {
            "type" => "rich_text_section",
            "elements" => [
              "type" => "text",
              "text" => "花王株式会社_ブランド横断の事例では、TVCMの残存週が業界傾向値（11週）と比べて13週と長いと報告されています。\n詳細は以下のファイルで確認できます。"
            ]
          },
          {
            "type" => "rich_text_list",
            "style" => "bullet",
            "indent" => 0,
            "elements" => [
              {
                "type" => "rich_text_section",
                "elements" => [
                  {"type" => "text", "text" => "ファイル: "},
                  {
                    "type" => "link",
                    "url" => "https://drive.google.com/file/d/1_t9ldOf-KcHxtC2fUS3sqCEJm8HwxMmU/preview?authuser=0",
                    "text" => "【花王様】横断レポート_20230116.pdf"
                  }
                ]
              },
              {
                "type" => "rich_text_section",
                "elements" => [
                  {
                    "type" => "text",
                    "text" => "該当部分: 「残存週は業界傾向値（11週）と比べて、13週と長い。」"
                  }
                ]
              }
            ]
          }
        ]
      },
      {"type" => "divider"},
    ]

    perform_enqueued_jobs

    assert_response :success

    actual_body = nil
    assert_slack_api_called(:post, "chat.postMessage") do |request|
      actual_body = decode_slack_client_request_body(request.body)
    end

    query = Query.find_by!(message: message)
    assert_kind_of Hash, query.body
    response = Response.find_by!(query: query)
    assert_kind_of Hash, response.body

    assert_equal(
      {
        "blocks" => [
          *expected_answer_blocks,
          feedback_action_block
        ],
        "channel" => channel.slack_id,
        "text" => expected_response,
        "thread_ts" => slack_ts,
      },
      actual_body
    )
  end


  test "app_mention event from a channel for Magellan RAG with --retrieval option" do
    skip "TODO"
    slack_ts = Time.now.to_f.to_s
    channel = conversations(:magellan_rag)
    user = users(:one)
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> --retrieval #{query_body}"

    any_instance_of(SlackBot::Application) do |klass|
      stub(klass).magellan_rag_channel? do |ch|
        ch.slack_id == channel.slack_id
      end
    end

    stub_slack_api(:post, "chat.postMessage").to_return(body: { "ok" => true, "ts" => Time.now.to_f.to_s }.to_json)

    # Check the case when missing reactions:write scope
    stub_slack_api(:post, "reactions.add").to_return { raise Slack::Web::Api::Errors::MissingScope, "missing_scope" }
    stub_slack_api(:post, "reactions.remove").to_return { raise Slack::Web::Api::Errors::MissingScope, "missing_scope" }

    assert Message.find_by(conversation: channel, user: user, slack_ts: slack_ts).blank?

    assert_enqueued_with(job: MagellanRagQueryJob) do
      params = {
        type: "event_callback",
        event: {
          type: "app_mention",
          text: query,
          channel: channel.slack_id,
          user: user.slack_id,
          ts: slack_ts
        }
      }
      request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
      timestamp = slack_ts.to_i
      headers = {
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": compute_request_signature(timestamp, request_body)
      }

      post "/slack/events", params:, headers:, as: :json
    end

    message = Message.find_by!(conversation: channel, user: user, slack_ts: slack_ts)
    assert_equal([
                   query_body,
                   slack_ts,
                 ],
                 [
                   message.text,
                   message.slack_thread_ts,
                 ])

    mock(Utils::MagellanRAG).endpoint do
      "http://report-rag-api.test"
    end

    stub_request(
      :get, "http://report-rag-api.test/retrieve_documents"
    ).with(
      query: {"query" => "ZZZ"}
    ).to_return_json(
      status: 200,
      body: [
        {
          "metadata" => {
            "company_name" => "Xica",
            "file_name" => "xica_report.pdf",
            "file_url" => "https://example.com/xyzzy/xica_report.pdf",
          },
          "content" => "ABC"
        }
      ]
    )

    expected_response = <<~END_BODY
    <@#{user.slack_id}> # Doc-0: Xica
    * file_name = xica_report.pdf
    * file_url = https://example.com/xyzzy/xica_report.pdf
    ABC
    END_BODY

    perform_enqueued_jobs

    assert_response :success

    actual_body = nil
    assert_slack_api_called(:post, "chat.postMessage") do |request|
      actual_body = decode_slack_client_request_body(request.body)
    end

    query = Query.find_by!(message: message)
    assert_kind_of Hash, query.body
    response = Response.find_by!(query: query)
    assert_kind_of Hash, response.body

    assert_equal(
      {
        "channel" => channel.slack_id,
        "text" => expected_response,
        "thread_ts" => slack_ts,
        "blocks" => [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => expected_response,
            }
          },
          feedback_action_block
        ]
      },
      actual_body
    )
  end
end
