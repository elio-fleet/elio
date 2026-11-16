require "application_system_test_case"

class FirstStartTest < ApplicationSystemTestCase
  setup do
    Invitation.delete_all
    Activity.delete_all
    User.delete_all
    AppSetting.current.update!(require_admin_two_factor: true)
  end

  test "first start: language, password strength, then 2FA and the overview" do
    visit root_path
    assert_selector "h2", text: "Créer le compte administrateur"

    within(".setup-languages") { click_on "English" }
    assert_selector "h2", text: "Create the administrator account"
    within(".setup-languages") { click_on "Français" }
    assert_selector "h2", text: "Créer le compte administrateur"

    fill_in "Email", with: "admin@example.com"
    fill_in "user_password", with: "short"
    assert_selector ".password-strength-label", text: "Trop court : au moins 12 caractères."
    fill_in "user_password", with: "password1234"
    assert_selector ".password-strength-label", text: "Faible"
    fill_in "user_password", with: "Vert-Sapin-Lune-42"
    assert_selector ".password-strength-label", text: "Mot de passe robuste."
    fill_in "user_password_confirmation", with: "Vert-Sapin-Lune-42"
    click_on "Créer le compte"

    # Straight to the mandatory 2FA, then to the overview.
    assert_selector "h1", text: "Activer la double authentification"
    secret = find(".two-factor-secret").text.delete(" ")
    find("input[name=code]").fill_in(with: ROTP::TOTP.new(secret).now)
    click_on "Activer"
    click_on "J'ai enregistré mes codes"

    assert_current_path root_path
    assert_equal "fr", AppSetting.current.reload.default_locale
    assert_equal "fr", User.sole.locale
  end
end
