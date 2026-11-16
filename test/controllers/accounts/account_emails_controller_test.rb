require "test_helper"

class AccountEmailsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper

  setup { @user = users(:viewer) }

  def ask(email = "new@example.com", password: "password1234")
    patch account_email_path, params: { user: { email: email, current_password: password } }
  end

  test "asking for a new email sends the link to it and a warning to the current one" do
    sign_in @user
    assert_enqueued_emails(2) { ask }

    assert_redirected_to account_path(anchor: "email")
    assert_equal "Un lien de confirmation a été envoyé à new@example.com. Votre email change une fois ce lien suivi.", flash[:notice]
    assert_equal "viewer@example.com", @user.reload.email
    assert_equal "new@example.com", @user.unconfirmed_email
    assert_empty Activity.of_kind(:user_email_changed)

    follow_redirect!
    assert_select "#email .email-change-pending", /new@example.com/
  end

  test "a wrong password or an unusable address changes nothing" do
    sign_in @user
    assert_no_enqueued_emails { ask(password: "wrong") }
    assert_equal "Le mot de passe actuel n'est pas valide", flash[:alert]

    assert_no_enqueued_emails { ask("operator@example.com") }
    assert_match "Le nouvel email", flash[:alert]
    assert_nil @user.reload.unconfirmed_email
  end

  test "the link of the email confirms the new address, signed in as the same user" do
    sign_in @user
    ask
    token = @user.reload.generate_token_for(:email_change)

    get confirm_account_email_path(token: token)

    assert_redirected_to account_path(anchor: "email")
    assert_equal "Votre email est désormais new@example.com.", flash[:notice]
    assert_equal "new@example.com", @user.reload.email
    assert_equal "viewer@example.com se connecte désormais avec new@example.com", Activity.of_kind(:user_email_changed).sole.summary

    get confirm_account_email_path(token: token)
    assert_match "n'est pas valide ou a expiré", flash[:alert]
  end

  test "the link does nothing for another user, and asks to sign in first" do
    @user.request_email_change("new@example.com", current_password: "password1234", confirm: true)
    token = @user.generate_token_for(:email_change)

    get confirm_account_email_path(token: token)
    assert_redirected_to new_user_session_path

    sign_in users(:operator)
    get confirm_account_email_path(token: token)
    assert_match "n'est pas valide ou a expiré", flash[:alert]
    assert_equal "viewer@example.com", @user.reload.email
  end

  test "the change waiting for its link can be cancelled" do
    sign_in @user
    ask
    token = @user.reload.generate_token_for(:email_change)

    delete account_email_path
    assert_equal "Changement d'email annulé.", flash[:notice]

    get confirm_account_email_path(token: token)
    assert_equal "viewer@example.com", @user.reload.email
  end

  test "without emails configured, the email changes at once" do
    Rails.configuration.x.mail_enabled = false
    sign_in @user

    assert_no_enqueued_emails { ask }

    assert_equal "Email modifié.", flash[:notice]
    assert_equal "new@example.com", @user.reload.email
    assert_equal 1, Activity.of_kind(:user_email_changed).count
    follow_redirect!
    assert_select "#email", /les emails ne sont pas configurés/i
  ensure
    Rails.configuration.x.mail_enabled = true
  end
end
