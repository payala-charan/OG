require "test_helper"

class PaymentFactorsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get payment_factors_index_url
    assert_response :success
  end

  test "should get upload" do
    get payment_factors_upload_url
    assert_response :success
  end
end
