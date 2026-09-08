require "test_helper"

class UploadedFilesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get uploaded_files_index_url
    assert_response :success
  end

  test "should get create" do
    get uploaded_files_create_url
    assert_response :success
  end

  test "should get destroy" do
    get uploaded_files_destroy_url
    assert_response :success
  end
end
