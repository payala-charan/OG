require "test_helper"

class PayorPreferencesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get payor_preferences_index_url
    assert_response :success
  end

  test "should get show" do
    get payor_preferences_show_url
    assert_response :success
  end
end
