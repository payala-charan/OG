require "test_helper"

class AutomationSchedulesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get automation_schedules_index_url
    assert_response :success
  end

  test "should get show" do
    get automation_schedules_show_url
    assert_response :success
  end

  test "should get create" do
    get automation_schedules_create_url
    assert_response :success
  end

  test "should get destroy" do
    get automation_schedules_destroy_url
    assert_response :success
  end
end
