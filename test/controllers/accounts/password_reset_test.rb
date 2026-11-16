require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include TwoFactorHelpers
  include StubHelpers

  test "the sign in page links to the password reset when emails can be sent" do
    get new_user_session_path
    assert_select "a.forgot-password[href=?]", new_user_password_path

    assert_select ".forgot-password-unavailable", 0

    Rails.configuration.x.mail_enabled = false
    get new_user_session_path
    assert_select "a.forgot-password", 0
    assert_select ".forgot-password-unavailable", /Aucun serveur d'email n'est configuré/
  ensure
    Rails.configuration.x.mail_enabled = true
  end

  test "without an email server, the reset page says so instead of pretending to send" do
    Rails.configuration.x.mail_enabled = false
    get new_user_password_path
    assert_redirected_to new_user_session_path
    assert_match "Aucun serveur d'email", flash[:alert]

    assert_no_enqueued_emails { post user_password_path, params: { user: { email: "one@example.com" } } }
    assert_redirected_to new_user_session_path
  ensure
    Rails.configuration.x.mail_enabled = true
  end

  test "the link is sent in the background, in the language of the user" do
    users(:one).update!(locale: "en")

    assert_enqueued_emails(1) { post user_password_path, params: { user: { email: "one@example.com" } } }
    assert_empty ActionMailer::Base.deliveries # nothing sent during the request
    perform_enqueued_jobs
    assert_equal "Reset password instructions", ActionMailer::Base.deliveries.last.subject
  end

  test "asking for a link never tells whether the email has an account" do
    get new_user_password_path
    assert_select "form[action=?] input[name='user[email]']", user_password_path

    assert_emails(1) { post user_password_path, params: { user: { email: "one@example.com" } } }
    known = flash[:notice]
    assert_emails(0) { post user_password_path, params: { user: { email: "nobody@example.com" } } }

    assert_equal known, flash[:notice]
    assert_redirected_to new_user_session_path
  end

  test "the emailed link sets a new password, without signing in (the second factor stays required)" do
    user = users(:one)
    enable_two_factor(user)
    perform_enqueued_jobs { post user_password_path, params: { user: { email: user.email } } }
    token = ActionMailer::Base.deliveries.last.body.encoded[/reset_password_token=([^"&\s]+)/, 1]
    assert token

    get edit_user_password_path(reset_password_token: token)
    assert_select "input[type=password][name='user[password]']"

    put user_password_path, params: { user: { reset_password_token: token, password: "new-password-42", password_confirmation: "new-password-42" } }

    assert_redirected_to new_user_session_path
    assert user.reload.valid_password?("new-password-42")
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "a reset signs out the other sessions and tells the owner by email" do
    user = users(:viewer)
    elsewhere = open_session
    elsewhere.post user_session_path, params: { user: { email: user.email, password: "password1234", remember_me: "1" } }
    elsewhere.get root_path
    assert_equal 200, elsewhere.response.status

    token = user.send_reset_password_instructions
    clear_enqueued_jobs
    perform_enqueued_jobs do
      put user_password_path, params: { user: { reset_password_token: token, password: "new-password-42", password_confirmation: "new-password-42" } }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ user.email ], mail.to
    assert_equal "Votre mot de passe Elio a été changé", mail.subject

    elsewhere.get root_path # neither the session nor the "remember me" cookie opens it any more
    assert_equal "http://www.example.com/users/sign_in", elsewhere.response.location
  end

  test "an invalid token is refused" do
    put user_password_path, params: { user: { reset_password_token: "nope", password: "new-password-42", password_confirmation: "new-password-42" } }

    assert_response :unprocessable_entity
    assert_not users(:one).reload.valid_password?("new-password-42")
  end

  test "an email that cannot be sent gets the same answer, never an error page" do
    failing = ->(*) { raise ArgumentError, "SMTP-AUTH requested but missing user name" }
    stub_method(User, :send_reset_password_instructions, failing) do
      post user_password_path, params: { user: { email: "one@example.com" } }
    end
    assert_redirected_to new_user_session_path
    assert_equal I18n.t("devise.passwords.send_paranoid_instructions"), flash[:notice]
  end
end
