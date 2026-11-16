require "test_helper"

# Sessions end after 30 minutes without a request (Devise timeoutable),
# unless "remember me" was ticked.
class SessionTimeoutTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers

  def sign_in_with_password(email, remember: false)
    post user_session_path, params: { user: { email: email, password: "password1234", remember_me: remember ? "1" : "0" } }
    assert_response :redirect
  end

  test "30 minutes without a request close the session" do
    sign_in_with_password("viewer@example.com")
    get servers_path
    assert_response :success

    travel 31.minutes do
      # Devise sends the expired request back to its page, which then asks to sign in.
      get servers_path
      assert_redirected_to servers_path
      follow_redirect!
      assert_redirected_to new_user_session_path
      follow_redirect!
      assert_response :success
      assert_equal "Votre session est expirée, veuillez vous reconnecter pour continuer.", flash[:alert]
    end
  end

  test "each request restarts the 30 minutes" do
    sign_in_with_password("viewer@example.com")

    travel 25.minutes
    get servers_path
    assert_response :success
    travel 25.minutes
    get servers_path
    assert_response :success, "50 minutes after the sign in, but 25 since the last request"
  end

  test "the session also expires after the second factor" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")
    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }
    get servers_path
    assert_response :success

    travel 31.minutes do
      get servers_path
      follow_redirect!
      assert_redirected_to new_user_session_path
    end
  end

  test "remember me keeps the user signed in past the 30 minutes" do
    sign_in_with_password("viewer@example.com", remember: true)

    travel 2.hours do
      get servers_path
      assert_response :success
    end
  end
end
