require "test_helper"
require "utils"

class UtilsMagellanRAGTest < ActiveSupport::TestCase
  test "generate_answer" do
    mock(Utils::MagellanRAG).endpoint do
      "http://report-rag-api.test"
    end

    stub_request(
      :get, "http://report-rag-api.test/generate_answer"
    ).with(
      query: {"query" => "TEST QUERY"}
    ).to_return_json(
      status: 200,
      body: {"answer": "TEST ANSWER"}
    )

    response = Utils::MagellanRAG.generate_answer("TEST QUERY")
    assert_equal(response,
                 {"answer" => "TEST ANSWER"})

    assert_requested(
      :get, "http://report-rag-api.test/generate_answer",
      query: {"query" => "TEST QUERY"}
    )
  end

  test "parse_answer" do
    answer_text = JSON.load(fixture_file_path("rag_answer.json").read)["answer"]
    answers = Utils::MagellanRAG.parse_answer(answer_text)

    assert_equal 9, answers.length
    assert_equal "花王株式会社_エッセンシャルの事例では、TVCMの残存週が他社（11週）と比べて13週と長いと報告されています。\n詳細は以下のファイルで確認できます。", answers[0].description
    assert_equal "【花王様】エッセンシャル_初回レポート報告_20221125.pdf", answers[0].file_name
    assert_equal "https://drive.google.com/file/d/1MB_IerrxHZ_Dn3ziT7vPixaOF_ng84D3/preview?authuser=0", answers[0].file_url
    assert_equal "「15秒・30秒・60秒ともに他施策と比べて効率は良好。残存週は他社（11週）と比べて、13週と長い。」", answers[0].matching_part
  end
end
