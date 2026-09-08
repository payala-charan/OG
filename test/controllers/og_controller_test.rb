require "test_helper"

class OgControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get og_index_url
    assert_response :success
  end

  test "should get upload" do
    get og_upload_url
    assert_response :success
  end
end
