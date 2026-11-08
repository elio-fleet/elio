require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "signing in through the form opens a session" do
    visit new_user_session_path
    fill_in "Email", with: "viewer@example.com"
    fill_in "Mot de passe", with: "password1234"
    click_on "Se connecter"

    assert_selector "h1", text: "Vue d'ensemble"
    within("nav.main-nav") { click_on "Serveurs" }
    assert_selector "h1", text: "Serveurs"
    assert_selector ".sidebar .user-role", text: "Lecture"
  end
end
