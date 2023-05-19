require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "default model is nil" do
    assert_nil Conversation.new.model
  end

  test "thread not allowed in default" do
    refute Conversation.new.thread_allowed?
  end
end
