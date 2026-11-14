require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @invitation = Invitation.create!(email: "dave@example.com", role: :operator, invited_by: users(:one))
  end

  def accept(password: "password1234", confirmation: password)
    post invitation_acceptance_path(@invitation.token), params: { user: { password: password, password_confirmation: confirmation } }
  end

  test "shows the invitation" do
    get invitation_acceptance_path(@invitation.token)

    assert_response :success
    assert_select "p", text: /one@example.com vous invite avec le rôle Opérateur/
    assert_select "input[name='user[email]'][readonly][value='dave@example.com']"
  end

  test "the page speaks the language of the invitation, not the browser's" do
    @invitation.update!(locale: "en")
    get invitation_acceptance_path(@invitation.token), headers: { "Accept-Language" => "fr-FR,fr;q=0.9" }

    assert_select "p", text: /one@example.com invites you with the role Operator/
  end

  test "accepting creates the account, signs in and logs it" do
    accept

    user = User.find_by!(email: "dave@example.com")
    assert user.operator?
    assert_redirected_to root_path
    assert_equal user, @invitation.reload.user
    activity = Activity.of_kind(:invitation_accepted).sole
    assert_equal [ user, "dave@example.com a rejoint Elio (Opérateur)" ], [ activity.user, activity.summary ]

    follow_redirect!
    assert_select ".sidebar .user-role", "Opérateur"
  end

  test "an invalid password re-renders the form" do
    accept(password: "password1234", confirmation: "different")

    assert_response :unprocessable_entity
    assert_select "#error_explanation li"
    assert @invitation.reload.pending?
  end

  test "the email cannot be changed" do
    post invitation_acceptance_path(@invitation.token), params: { user: { email: "evil@example.com", password: "password1234", password_confirmation: "password1234" } }

    assert User.exists?(email: "dave@example.com")
    assert_not User.exists?(email: "evil@example.com")
  end

  test "unknown, expired, revoked and used links are refused" do
    expired = Invitation.create!(email: "e@example.com", invited_by: users(:one)).tap { |i| i.update_columns(expires_at: 1.minute.ago) }
    revoked = Invitation.create!(email: "r@example.com", invited_by: users(:one)).tap(&:revoke!)
    accept
    delete destroy_user_session_path

    [ "nope", expired.token, revoked.token, @invitation.token ].each do |token|
      get invitation_acceptance_path(token)
      assert_response :not_found
      assert_select "h2", "Invitation invalide"
    end
  end

  test "a signed in user is sent back to the dashboard" do
    sign_in users(:viewer)
    get invitation_acceptance_path(@invitation.token)

    assert_redirected_to root_path
    assert_match "déjà connecté", flash[:alert]
  end
end
