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
end
