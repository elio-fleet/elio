require "test_helper"

class SettingsUsersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include TwoFactorHelpers

  test "lists the users and the pending invitations with their link" do
    invitation = Invitation.create!(email: "dave@example.com", role: :operator, invited_by: users(:one))
    Invitation.create!(email: "old@example.com", invited_by: users(:one)).revoke!
    sign_in users(:one)

    get settings_users_path

    assert_select "#users li.user-row", 3
    assert_select "#users li", text: /one@example.com \(vous\)/
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:one))} button", text: "Désactiver", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:operator))}" do
      assert_select "select[name='user[role]'] option[selected][value=operator]"
      assert_select "form[action=?][data-turbo-confirm]", deactivate_settings_user_path(users(:operator))
      assert_select "p", text: /Jamais connecté\s+· 2FA désactivée/
    end
    assert_select "li.pending-invitation", 1 do
      assert_select "p", text: /dave@example.com\s+Opérateur/
      assert_select "input.invitation-link[value=?]", invitation_acceptance_url(invitation.token)
      assert_select "form[action=?][data-turbo-confirm]", settings_invitation_path(invitation)
    end
  end

  test "an admin invites someone, by email when emails can be sent" do
    sign_in users(:one)

    assert_enqueued_email_with InvitationMailer, :invite, args: ->(args) { args.first.email == "dave@example.com" } do
      post settings_invitations_path, params: { invitation: { email: "Dave@example.com", role: "operator" } }
    end

    invitation = Invitation.sole
    assert_equal [ "dave@example.com", "operator", users(:one) ], [ invitation.email, invitation.role, invitation.invited_by ]
    assert_redirected_to settings_users_path
    assert_equal "Invitation envoyée par email à dave@example.com. Le lien reste copiable ci-dessous.", flash[:notice]
    assert_equal "dave@example.com invité (Opérateur)", Activity.of_kind(:user_invited).sole.summary
  end

  test "an invalid invitation is explained" do
    sign_in users(:one)

    post settings_invitations_path, params: { invitation: { email: "operator@example.com", role: "viewer" } }

    assert_equal 0, Invitation.count
    assert_match "correspond déjà à un utilisateur", flash[:alert]
  end

  test "an admin revokes a pending invitation" do
    invitation = Invitation.create!(email: "dave@example.com", invited_by: users(:one))
    sign_in users(:one)

    delete settings_invitation_path(invitation)

    assert_equal :revoked, invitation.reload.status
    assert_redirected_to settings_users_path
    assert_equal "Invitation de dave@example.com révoquée", Activity.of_kind(:invitation_revoked).sole.summary
  end

  test "an invitation that is no longer pending cannot be revoked" do
    invitation = Invitation.create!(email: "dave@example.com", invited_by: users(:one)).tap(&:revoke!)
    sign_in users(:one)

    delete settings_invitation_path(invitation)

    assert_response :not_found
  end

  test "changing a role is logged" do
    sign_in users(:one)

    patch settings_user_path(users(:viewer)), params: { user: { role: "operator" } }

    assert users(:viewer).reload.operator?
    assert_redirected_to settings_users_path
    assert_equal "Rôle de viewer@example.com : Lecture → Opérateur", Activity.of_kind(:user_role_changed).sole.summary
  end

  test "the last admin cannot demote themselves" do
    sign_in users(:one)

    patch settings_user_path(users(:one)), params: { user: { role: "viewer" } }

    assert users(:one).reload.admin?
    assert_match "au moins un administrateur actif", flash[:alert]
  end

  test "deactivating and reactivating an account" do
    sign_in users(:one)

    post deactivate_settings_user_path(users(:operator))
    assert users(:operator).reload.deactivated?
    assert_equal "operator@example.com désactivé", Activity.of_kind(:user_deactivated).sole.summary

    post reactivate_settings_user_path(users(:operator))
    assert_not users(:operator).reload.deactivated?
    assert_equal "operator@example.com réactivé", Activity.of_kind(:user_reactivated).sole.summary
  end

  test "an admin cannot deactivate their own account" do
    users(:operator).update!(role: :admin)
    sign_in users(:one)

    post deactivate_settings_user_path(users(:one))

    assert_not users(:one).reload.deactivated?
    assert_equal "Vous ne pouvez pas désactiver votre propre compte.", flash[:alert]
  end

  test "a deactivated user is signed out on their next request and cannot sign in again" do
    sign_in users(:operator)
    get root_path
    assert_response :success

    users(:operator).deactivate!
    get root_path
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { email: "operator@example.com", password: "password1234" } }
    follow_redirect! while response.redirect?
    assert_select "#flash", text: /Ce compte a été désactivé/
  end

  test "signing in records the last sign in" do
    post user_session_path, params: { user: { email: "viewer@example.com", password: "password1234" } }

    assert_equal 1, users(:viewer).reload.sign_in_count
    assert_not_nil users(:viewer).last_sign_in_at
  end

  test "an admin makes 2FA optional or mandatory for admins" do
    users(:one).tap { |admin| enable_two_factor(admin) }
    sign_in users(:one)

    patch settings_security_path, params: { app_setting: { require_admin_two_factor: "1" } }
    assert AppSetting.current.require_admin_two_factor
    assert_equal "Double authentification obligatoire pour les administrateurs.", flash[:notice]

    patch settings_security_path, params: { app_setting: { require_admin_two_factor: "1", require_operator_two_factor: "1" } }
    assert_equal "Double authentification obligatoire pour les administrateurs et opérateurs.", flash[:notice]

    patch settings_security_path, params: { app_setting: { require_admin_two_factor: "0", require_operator_two_factor: "0" } }
    assert_not AppSetting.current.reload.require_admin_two_factor
    assert_equal "Double authentification facultative pour tous.", flash[:notice]
  end

  test "operators must set up 2FA when it is mandatory for them, viewers never (AUDIT.md S20)" do
    AppSetting.current.update!(require_operator_two_factor: true)
    sign_in users(:operator)
    get servers_path
    assert_redirected_to new_two_factor_path

    sign_in users(:viewer)
    get servers_path
    assert_response :success
  end

  test "an admin unlocks an account before the end of its lock" do
    users(:operator).lock_access!
    sign_in users(:one)

    get settings_users_path
    row = "##{ActionView::RecordIdentifier.dom_id(users(:operator))}"
    assert_select "#{row} .user-state", "Verrouillé"
    assert_select "#{row} form[action=?]", unlock_settings_user_path(users(:operator))
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:viewer))} form[action=?]", unlock_settings_user_path(users(:viewer)), count: 0

    post unlock_settings_user_path(users(:operator))

    assert_redirected_to settings_users_path
    assert_equal "operator@example.com peut de nouveau se connecter.", flash[:notice]
    assert_not users(:operator).reload.access_locked?
    assert_equal 0, users(:operator).failed_attempts
    assert_equal "operator@example.com déverrouillé", Activity.of_kind(:user_unlocked).sole.summary
  end

  test "an admin resets the 2FA of someone who lost it" do
    enable_two_factor(users(:operator))
    sign_in users(:one)

    get settings_users_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:operator))} .user-two-factor", "2FA activée"

    post reset_two_factor_settings_user_path(users(:operator))

    assert_not users(:operator).reload.two_factor_enabled?
    assert_equal "2FA de operator@example.com réinitialisée par one@example.com", Activity.of_kind(:two_factor_disabled).sole.summary
  end

  test "without emails, the invitation link is to be copied" do
    Rails.configuration.x.mail_enabled = false
    sign_in users(:one)

    assert_no_enqueued_emails { post settings_invitations_path, params: { invitation: { email: "eve@example.com", role: "viewer" } } }
    assert_equal "Invitation créée pour eve@example.com. Copiez le lien et envoyez-le-lui.", flash[:notice]
  ensure
    Rails.configuration.x.mail_enabled = true
  end
end
