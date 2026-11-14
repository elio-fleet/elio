require "test_helper"

class TwoFactorSignInTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers

  def sign_in_with_password(email, remember: false)
    post user_session_path, params: { user: { email: email, password: "password1234", remember_me: remember ? "1" : "0" } }
  end

  test "without 2FA the password signs in directly" do
    sign_in_with_password("viewer@example.com")

    assert_redirected_to root_path
    assert_equal 1, users(:viewer).reload.sign_in_count
    get servers_path
    assert_response :success, "the session must be open"
  end

  test "with 2FA the password alone does not open a session" do
    enable_two_factor(users(:operator))

    sign_in_with_password("operator@example.com")
    assert_redirected_to new_two_factor_challenge_path
    assert_nil session["warden.user.user.key"], "no session before the second factor"

    get root_path
    assert_redirected_to new_user_session_path
    assert_equal 0, users(:operator).reload.sign_in_count
  end

  test "a wrong password never reaches the second step" do
    enable_two_factor(users(:operator))
    post user_session_path, params: { user: { email: "operator@example.com", password: "nope" } }

    assert_response :unprocessable_entity
    get new_two_factor_challenge_path
    assert_redirected_to new_user_session_path
  end

  test "a valid code completes the sign in" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")

    get new_two_factor_challenge_path
    assert_select "input[name=code][autocomplete=one-time-code]"

    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".sidebar .user-role", "Opérateur"
    assert_equal 1, users(:operator).reload.sign_in_count
  end

  test "remember me is kept through the second step" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com", remember: true)

    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }

    assert cookies[:remember_user_token].present?
  end

  test "a wrong or reused code is refused" do
    enable_two_factor(users(:operator))
    code = next_totp(users(:operator))
    users(:operator).verify_two_factor(code) # already used elsewhere
    sign_in_with_password("operator@example.com")

    post two_factor_challenge_path, params: { code: "000000" }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /\ACode invalide ou déjà utilisé\./

    post two_factor_challenge_path, params: { code: code }
    assert_response :unprocessable_entity
  end

  test "a backup code works and is logged" do
    codes = enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")

    post two_factor_challenge_path, params: { code: codes.first }

    assert_redirected_to root_path
    activity = Activity.of_kind(:two_factor_backup_code_used).sole
    assert_equal "operator@example.com s'est connecté avec un code de secours (9 restants)", activity.summary
  end

  test "the owner is told by email when a backup code is used, not for a code of the app" do
    codes = enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")
    assert_no_enqueued_emails { post two_factor_challenge_path, params: { code: next_totp(users(:operator)) } }
    delete destroy_user_session_path

    sign_in_with_password("operator@example.com")
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post two_factor_challenge_path, params: { code: codes.first } }

    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "operator@example.com" ], mail.to
    assert_match "(adresse IP : 127.0.0.1)", mail.body.to_s
  end

  test "a wrong code says how many attempts are left" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")

    post two_factor_challenge_path, params: { code: "000000" }

    assert_select "#error_explanation", "Code invalide ou déjà utilisé. Encore 9 essais avant que votre compte soit verrouillé pendant 15 minutes."
  end

  test "the second step expires after 5 minutes" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")

    travel 6.minutes do
      post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }
    end

    assert_redirected_to new_user_session_path
    assert_match "expirée", flash[:alert]
  end

  test "a deactivated account cannot finish the second step" do
    enable_two_factor(users(:operator))
    sign_in_with_password("operator@example.com")
    users(:operator).deactivate!

    post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }

    assert_redirected_to new_user_session_path
  end

  test "the challenge page needs a pending sign in" do
    get new_two_factor_challenge_path
    assert_redirected_to new_user_session_path
  end
end
