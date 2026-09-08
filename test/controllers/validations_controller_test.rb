require "test_helper"

class ValidationsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get validations_index_url
    assert_response :success
  end

  test "should get upload" do
    get validations_upload_url
    assert_response :success
  end
end
