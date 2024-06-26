require "test_helper"

class RootTest < ActionDispatch::IntegrationTest
  test "visiting /" do
    get "/"
    assert_response :success
  end
end
