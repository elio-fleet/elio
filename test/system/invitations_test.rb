require "application_system_test_case"

class InvitationsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "an admin invites an operator who joins through the link" do
    sign_in users(:one)
    visit settings_users_path

    fill_in "Email", with: "dave@example.com"
    select "Opérateur", from: "Rôle"
    click_on "Créer l'invitation"

    assert_text "Invitation envoyée par email à dave@example.com."
    link = find("input.invitation-link").value
    assert_match %r{/invitations/\S+\z}, link

    find(".sidebar button[title='Déconnexion']").click
    assert_selector "h2", text: "Connexion"

    visit URI(link).path
    assert_text "one@example.com vous invite avec le rôle Opérateur"
    fill_in "Mot de passe", with: "password1234", match: :prefer_exact
    fill_in "Confirmation du mot de passe", with: "password1234"
    click_on "Créer mon compte"

    assert_text "Bienvenue sur Elio !"
    assert_selector ".sidebar .user-role", text: "Opérateur"
    assert_no_selector "nav a[title=Paramètres]"
  end

  test "an admin invites two people at once and resends an expired invitation" do
    expired = Invitation.create!(email: "old@example.com", invited_by: users(:one)).tap { |i| i.update_columns(expires_at: 1.day.ago) }
    sign_in users(:one)
    visit settings_users_path

    fill_in "Email", with: "dave@example.com, erin@example.com"
    click_on "Créer l'invitation"

    assert_text "2 invitations envoyées par email : dave@example.com et erin@example.com."
    assert_selector "li.pending-invitation", count: 2

    within("##{ActionView::RecordIdentifier.dom_id(expired)}") { click_on "Renvoyer" }

    assert_text "Invitation envoyée par email à old@example.com."
    assert_selector "li.pending-invitation", count: 3
    assert_no_selector "li.expired-invitation"
  end
end
