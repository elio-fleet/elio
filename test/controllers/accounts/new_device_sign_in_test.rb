require "test_helper"

# The owner of an account is emailed when it signs in from a browser it never
# signed in from (KnownDevices).
class NewDeviceSignInTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include TwoFactorHelpers

  setup { users(:viewer).update_column(:sign_in_count, 3) }

  def sign_in_with(password, email: "viewer@example.com")
    post user_session_path, params: { user: { email: email, password: password } }
  end

  def sign_out
    delete destroy_user_session_path
  end

  test "a new browser sends an email in the background, a known one does not" do
    assert_enqueued_email_with AccountMailer, :new_device_sign_in, args: ->(args) { args.first == users(:viewer) && args.last[:ip] == "127.0.0.1" } do
      sign_in_with("password1234")
    end
    assert_redirected_to root_path

    sign_out
    assert_no_enqueued_emails do
      sign_in_with("password1234")
    end
    assert_redirected_to root_path

    reset! # another browser
    assert_enqueued_emails 1 do
      sign_in_with("password1234")
    end
  end

  test "a browser remembers each account that signed in from it" do
    users(:operator).update_column(:sign_in_count, 3)
    assert_enqueued_emails 2 do
      sign_in_with("password1234")
      sign_out
      sign_in_with("password1234", email: "operator@example.com")
      sign_out
    end

    assert_no_enqueued_emails do
      sign_in_with("password1234")
      sign_out
      sign_in_with("password1234", email: "operator@example.com")
    end
  end

  test "nothing is sent for a wrong password, nor before the second factor" do
    enable_two_factor(users(:operator))
    users(:operator).update_column(:sign_in_count, 3)

    assert_no_enqueued_emails do
      sign_in_with("wrong")
      sign_in_with("password1234", email: "operator@example.com")
    end
    assert_redirected_to new_two_factor_challenge_path

    assert_enqueued_email_with AccountMailer, :new_device_sign_in, args: ->(args) { args.first == users(:operator) } do
      post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }
    end
  end

  test "a backup code sends only its own email, and the browser is then known" do
    codes = enable_two_factor(users(:operator))
    users(:operator).update_column(:sign_in_count, 3)
    sign_in_with("password1234", email: "operator@example.com")

    assert_enqueued_emails 1 do
      post two_factor_challenge_path, params: { code: codes.first }
    end
    assert_enqueued_email_with AccountMailer, :backup_code_used, args: ->(args) { args.first == users(:operator) }

    sign_out
    sign_in_with("password1234", email: "operator@example.com")
    assert_no_enqueued_emails do
      post two_factor_challenge_path, params: { code: next_totp(users(:operator)) }
    end
  end

  test "the first sign in of an account sends nothing" do
    users(:viewer).update_column(:sign_in_count, 0)

    assert_no_enqueued_emails do
      sign_in_with("password1234")
    end
  end

  test "the browser that accepted an invitation is known at the next sign in" do
    invitation = Invitation.create!(email: "dave@example.com", role: :operator, invited_by: users(:one))

    assert_no_enqueued_emails do
      post invitation_acceptance_path(invitation.token), params: { user: { password: "password1234", password_confirmation: "password1234" } }
      sign_out
      sign_in_with("password1234", email: "dave@example.com")
    end
    assert_redirected_to root_path

    reset!
    assert_enqueued_emails 1 do
      sign_in_with("password1234", email: "dave@example.com")
    end
  end

  test "nothing is sent when no mail server is configured" do
    Rails.configuration.x.mail_enabled = false

    assert_no_enqueued_emails do
      sign_in_with("password1234")
    end
    assert_redirected_to root_path
  ensure
    Rails.configuration.x.mail_enabled = true
  end
end
