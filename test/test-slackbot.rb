class TestSlackBot < Test::Unit::TestCase
  data(
    "gpt-4" => ["gpt-4", 0.03r/1000],
    "gpt-4-0314" => ["gpt-4-0314", 0.03r/1000],
    "gpt-3.5-turbo" => ["gpt-3.5-turbo", 0.002r/1000],
    "gpt-3.5-turbo-0301" => ["gpt-3.5-turbo-0301", 0.002r/1000]
  )
  def test_prompt_unit_price(data)
    model, expected = *data
    assert_equal expected, SlackBot.prompt_unit_price(model)
  end

  data(
    "gpt-4" => ["gpt-4", 0.06r/1000],
    "gpt-4-0314" => ["gpt-4-0314", 0.06r/1000],
    "gpt-3.5-turbo" => ["gpt-3.5-turbo", 0.002r/1000],
    "gpt-3.5-turbo-0301" => ["gpt-3.5-turbo-0301", 0.002r/1000]
  )
  def test_completion_unit_price(data)
    model, expected = *data
    assert_equal expected, SlackBot.completion_unit_price(model)
  end
end
