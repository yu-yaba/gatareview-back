require 'test_helper'

class LecturesControllerTest < ActionDispatch::IntegrationTest
  test 'should get reviews' do
    get lectures_reviews_url
    assert_response :success
  end
end
