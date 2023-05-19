require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "default model is nil" do
    assert_nil Conversation.new.model
  end

  test "thread allowed in default" do
    assert Conversation.new.thread_allowed?
  end
end
