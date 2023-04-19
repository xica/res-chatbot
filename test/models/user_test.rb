require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "not admin in default" do
    refute User.new.admin
  end
end
