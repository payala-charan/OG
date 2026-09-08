require "test_helper"

class PayorsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get payors_index_url
    assert_response :success
  end

  test "should get upload" do
    get payors_upload_url
    assert_response :success
  end
end
