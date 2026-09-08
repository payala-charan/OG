require "test_helper"

class SheetsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get sheets_index_url
    assert_response :success
  end

  test "should get upload" do
    get sheets_upload_url
    assert_response :success
  end
end
