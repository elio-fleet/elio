require "test_helper"

class JobsDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include TwoFactorHelpers

  test "requires to be signed in" do
    get "/jobs"
    assert_redirected_to new_user_session_path
  end

  test "operators and viewers are sent back to the overview" do
    %i[operator viewer].each do |user|
      sign_in users(user)
      get "/jobs"
      assert_redirected_to "/" # (after a request to the engine, the route helpers are the engine's)
      assert_match "suivi technique des jobs", flash[:alert]
    end
  end

  test "admins see the jobs dashboard" do
    sign_in users(:one)
    get "/jobs"
    follow_redirect! while response.redirect?
    assert_response :success
    assert_select "a", text: /Failed jobs/
  end

  test "an admin without the required 2FA goes to their account first" do
    app_settings(:main).update!(require_admin_two_factor: true)
    sign_in users(:one)
    get "/jobs"
    assert_redirected_to "/account"
  end

  test "the French translations survive a visit to the dashboard" do
    sign_in users(:one)
    get "/jobs"
    follow_redirect! while response.redirect?

    get "/journal"
    assert_response :success
    assert_equal "jeudi", I18n.t("date.day_names", locale: :fr)[4]
  end
end
