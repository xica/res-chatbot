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

    rag_answer = <<~END_ANSWER.strip
    花王株式会社_エッセンシャルの事例では、TVCMの残存週が他社（11週）と比べて13週と長いと報告されています。
    詳細は以下のファイルで確認できます。
    - ファイル名: 【花王様】エッセンシャル_初回レポート報告_20221125.pdf
    - ファイルのURL: [こちら](https://drive.google.com/file/d/1MB_IerrxHZ_Dn3ziT7vPixaOF_ng84D3/preview?authuser=0)
    - 該当部分: 「15秒・30秒・60秒ともに他施策と比べて効率は良好。残存週は他社（11週）と比べて、13週と長い。」
    END_ANSWER
    expected_response = "<@#{user.slack_id}> 次の1件の文書が質問に該当する可能性があります。\n\n#{rag_answer}"

    mock(Utils::MagellanRAG).generate_answer(message.text) do
      {"answer" => rag_answer}
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
        "thread_ts" => message.slack_thread_ts,
        "text" => expected_response,
        "blocks" => [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => expected_response.each_line.first.strip,
            },
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
          feedback_action_block
        ]
      },
      actual_body
    )
  end

  test "query = 成果最大化シミュレーションを実施した事例を教えてください" do
    skip "TODO"
    message = messages(:report_query_one)
    channel = message.conversation
    user = message.user

    rag_answer = JSON.load(fixture_file_path("rag_answer-002.json").read)["answer"]
    # p rag_answer
  end
end
