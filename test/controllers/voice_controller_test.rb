require "test_helper"

class VoiceControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get voice_index_url
    assert_response :success
  end
end
