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

  test "the permissions matrix shows what each role can do, from User::PERMISSIONS" do
    sign_in users(:one)

    get settings_users_path

    assert_select "#roles table.permissions-matrix" do
      assert_equal [ "Droit", "Admin", "Opérateur", "Lecture" ], css_select("thead th").map { |th| th.text.strip }
      assert_select "tbody tr", User::PERMISSIONS.size
      assert_select "#permission-view .allowed", 3
      assert_select "#permission-operate .allowed", 2
      assert_select "#permission-operate td:last-child .denied"
      assert_select "#permission-administer .allowed", 1
      assert_select "#permission-administer th", text: /Administrer Elio/
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

  test "an admin invites several addresses at once; the invalid ones are explained" do
    sign_in users(:one)

    assert_enqueued_emails 2 do
      post settings_invitations_path, params: { invitation: { email: "dave@example.com, Erin@example.com,operator@example.com, nope", role: "operator", locale: "en" } }
    end

    assert_equal [ [ "dave@example.com", "operator", "en" ], [ "erin@example.com", "operator", "en" ] ],
                 Invitation.order(:email).pluck(:email, :role, :locale)
    assert_equal "2 invitations envoyées par email : dave@example.com et erin@example.com. Les liens restent copiables ci-dessous.", flash[:notice]
    assert_match "operator@example.com (L'email correspond déjà à un utilisateur", flash[:alert]
    assert_match "nope (L'email n'est pas valide)", flash[:alert]
    assert_equal 2, Activity.of_kind(:user_invited).count
  end

  test "at most 20 addresses at once" do
    sign_in users(:one)

    post settings_invitations_path, params: { invitation: { email: (1..21).map { |n| "user#{n}@example.com" }.join(","), role: "viewer" } }

    assert_equal 0, Invitation.count
    assert_equal "Au plus 20 adresses à la fois.", flash[:alert]
  end

  test "expired invitations are listed and resent in one click, with a new link" do
    invitation = Invitation.create!(email: "dave@example.com", role: :operator, invited_by: users(:operator))
    invitation.update_columns(expires_at: 2.days.ago)
    old_token = invitation.token
    sign_in users(:one)

    get settings_users_path
    assert_select "li.pending-invitation", 0
    assert_select "li.expired-invitation", 1 do
      assert_select "p", text: /Par operator@example.com · expirée il y a 2 jours/
      assert_select "form[action=?] button", resend_settings_invitation_path(invitation), text: "Renvoyer"
    end

    assert_enqueued_email_with InvitationMailer, :invite, args: [ invitation ] do
      post resend_settings_invitation_path(invitation)
    end

    assert_redirected_to settings_users_path
    assert invitation.reload.pending?
    assert_equal users(:one), invitation.invited_by
    assert_equal "Invitation envoyée par email à dave@example.com. Le lien reste copiable ci-dessous.", flash[:notice]
    assert_equal "dave@example.com invité (Opérateur)", Activity.of_kind(:user_invited).sole.summary
    get settings_users_path
    assert_select "li.pending-invitation input.invitation-link[value=?]", invitation_acceptance_url(invitation.token)
    assert_not_equal old_token, invitation.token
    sign_out users(:one)
    get invitation_acceptance_path(old_token)
    assert_select "h2", text: "Invitation invalide"
    get invitation_acceptance_path(invitation.token)
    assert_select "h2", text: "Rejoindre Elio"
  end

  test "an expired invitation is not resent once the address was invited again" do
    invitation = Invitation.create!(email: "dave@example.com", invited_by: users(:one)).tap { |i| i.update_columns(expires_at: 1.day.ago) }
    Invitation.create!(email: "dave@example.com", invited_by: users(:one))
    sign_in users(:one)

    assert_no_enqueued_emails { post resend_settings_invitation_path(invitation) }

    assert invitation.reload.expired?
    assert_match "dave@example.com (L'email", flash[:alert]
  end

  test "a pending or revoked invitation cannot be resent" do
    pending = Invitation.create!(email: "dave@example.com", invited_by: users(:one))
    revoked = Invitation.create!(email: "erin@example.com", invited_by: users(:one)).tap(&:revoke!)

    [ pending, revoked ].each do |invitation|
      sign_in users(:one)
      post resend_settings_invitation_path(invitation)
      assert_response :not_found
    end
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

  test "deactivate and reactivate are at the same place: the actions menu of the row" do
    users(:viewer).deactivate!
    sign_in users(:one)

    get settings_users_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:operator))} [role=menu]" do
      assert_select "form[action=?] button[role=menuitem]", deactivate_settings_user_path(users(:operator)), text: "Désactiver"
      assert_select "form[action=?]", reactivate_settings_user_path(users(:operator)), count: 0
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:viewer))}" do
      assert_select "[role=menu] form[action=?] button[role=menuitem]", reactivate_settings_user_path(users(:viewer)), text: "Réactiver"
      assert_select "form[action=?]", deactivate_settings_user_path(users(:viewer)), count: 0
      assert_select "form[action=?]", require_password_change_settings_user_path(users(:viewer)), count: 0
    end
  end

  test "each account links to its actions in the journal and shows its last action" do
    Current.user = users(:operator)
    Activity.record!(:server_created, server: Server.first).update_columns(created_at: 3.days.ago)
    Current.user = nil
    sign_in users(:one)

    get settings_users_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:operator))}" do
      assert_select "p", text: /dernière action il y a 3 jours/
      assert_select "[role=menu] a[href=?]", activities_path(q: "operator@example.com"), text: "Ses actions dans le journal"
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:viewer))} .user-last-action", 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:one))} [role=menu] a[href=?]", activities_path(q: "one@example.com")

    get activities_path(q: "operator@example.com")
    assert_select "#activities li", 1
  end

  test "an admin asks for a new password: the account goes to My account until it is chosen" do
    sign_in users(:one)

    post require_password_change_settings_user_path(users(:operator))

    assert_redirected_to settings_users_path
    assert users(:operator).reload.password_change_required?
    assert_equal "operator@example.com devra choisir un nouveau mot de passe avant de continuer.", flash[:notice]
    assert_equal "operator@example.com doit choisir un nouveau mot de passe (demandé par one@example.com)",
                 Activity.of_kind(:password_change_required).sole.summary
    get settings_users_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:operator))}" do
      assert_select ".user-password-change", "Doit changer son mot de passe"
      assert_select "form[action=?]", require_password_change_settings_user_path(users(:operator)), count: 0
    end

    sign_in users(:operator)
    get servers_path
    assert_redirected_to account_path(anchor: "password")
    get account_path
    assert_select "#password .password-change-required", /Un administrateur vous demande/

    patch password_account_path, params: { user: { current_password: "password1234", password: "password1234", password_confirmation: "password1234" } }
    assert_response :unprocessable_entity
    assert users(:operator).reload.password_change_required?

    patch password_account_path, params: { user: { current_password: "password1234", password: "new-password-5678", password_confirmation: "new-password-5678" } }
    assert_redirected_to account_path
    assert_not users(:operator).reload.password_change_required?
    get servers_path
    assert_response :success
  end

  test "an admin changes their own password in My account, not through the request" do
    sign_in users(:one)

    post require_password_change_settings_user_path(users(:one))

    assert_redirected_to account_path(anchor: "password")
    assert_not users(:one).reload.password_change_required?
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
