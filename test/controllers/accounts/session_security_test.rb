require "test_helper"

class SessionSecurityTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers

  def sign_in_with(password, email: "viewer@example.com")
    post user_session_path, params: { user: { email: email, password: password } }
  end

  test "10 wrong passwords lock the account for 15 minutes" do
    sign_in_with("wrong")
    assert_equal "Email ou mot de passe incorrect. Après 10 échecs de suite, un compte est verrouillé pendant 15 minutes.", flash[:alert],
                 "the lock rule is stated, the same for every email"
    8.times { sign_in_with("wrong") }
    assert_not users(:viewer).reload.access_locked?
    assert_match "Encore un essai", flash[:alert].to_s, "the last attempt is announced"

    sign_in_with("wrong")
    assert users(:viewer).reload.access_locked?
    assert_equal "viewer@example.com verrouillé après 10 essais ratés", Activity.of_kind(:user_locked).sole.summary

    sign_in_with("password1234")
    assert_response :unprocessable_entity
    assert_match "verrouillé pendant 15 minutes au plus", flash[:alert].to_s
    get root_path
    assert_redirected_to new_user_session_path

    travel 16.minutes do
      sign_in_with("password1234")
      assert_redirected_to root_path
      get servers_path
      assert_response :success
    end
  end

  test "an unknown email gets the same answer as a wrong password" do
    sign_in_with("wrong", email: "nobody@example.com")
    unknown = flash[:alert]
    sign_in_with("wrong")

    assert_equal unknown, flash[:alert]
  end

  test "a successful sign in resets the failed attempts" do
    5.times { sign_in_with("wrong") }
    sign_in_with("password1234")

    assert_equal 0, users(:viewer).reload.failed_attempts
  end

  test "wrong 2FA codes count as failed attempts and lock the account" do
    enable_two_factor(users(:operator))
    sign_in_with("password1234", email: "operator@example.com")

    9.times do
      post two_factor_challenge_path, params: { code: "000000" }
      assert_response :unprocessable_entity
    end
    post two_factor_challenge_path, params: { code: "000000" }

    assert_redirected_to new_user_session_path
    assert_match "verrouillé pendant 15 minutes", flash[:alert]
    assert users(:operator).reload.access_locked?
    assert_equal 1, Activity.of_kind(:user_locked).count
  end

  test "typing the password again does not give new guesses of the 2FA code" do
    enable_two_factor(users(:operator))
    sign_in_with("password1234", email: "operator@example.com")
    5.times { post two_factor_challenge_path, params: { code: "000000" } }
    assert_select "#error_explanation", /Encore 5 essais/

    sign_in_with("password1234", email: "operator@example.com")
    assert_equal 5, users(:operator).reload.failed_attempts, "a right password alone completes nothing"
    5.times { post two_factor_challenge_path, params: { code: "000000" } }

    assert users(:operator).reload.access_locked?
  end

  test "a valid 2FA code resets the failed attempts" do
    enable_two_factor(users(:operator))
    sign_in_with("password1234", email: "operator@example.com")
    3.times { post two_factor_challenge_path, params: { code: "000000" } }

    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }

    assert_redirected_to root_path
    assert_equal 0, users(:operator).reload.failed_attempts
  end

  test "a locked account cannot finish a pending 2FA step" do
    enable_two_factor(users(:operator))
    sign_in_with("password1234", email: "operator@example.com")
    users(:operator).lock_access!

    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }

    assert_redirected_to new_user_session_path
  end

  test "the session expires after 30 minutes of inactivity" do
    sign_in_with("password1234")

    travel 29.minutes do
      get root_path
      assert_response :success
    end

    travel 60.minutes do
      get servers_path
      # Devise signs out and sends back to the requested page, which asks to sign in.
      assert_redirected_to servers_url
      assert_match "Votre session est expirée", flash[:alert].to_s
      follow_redirect!
      assert_redirected_to new_user_session_path
    end
  end
end
