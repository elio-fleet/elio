require "application_system_test_case"

class TwoFactorTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "enabling 2FA, then signing in with a code" do
    sign_in users(:operator)
    visit root_path
    find(".sidebar a.account-link").click
    click_on "Activer la double authentification"

    assert_selector ".two-factor-qr img"
    secret = find(".two-factor-secret").text.delete(" ")
    find("input[name=code]").fill_in(with: ROTP::TOTP.new(secret).now)
    click_on "Activer"

    assert_text "Double authentification activée."
    assert_selector "textarea.backup-codes"
    click_on "J'ai enregistré mes codes"
    assert_selector ".two-factor-state", text: "Activée"

    find(".sidebar button[title='Déconnexion']").click
    fill_in "Email", with: "operator@example.com"
    fill_in "Mot de passe", with: "password1234"
    click_on "Se connecter"

    assert_selector "h2", text: "Double authentification"
    fill_in "Code", with: ROTP::TOTP.new(secret).at(Time.now + 30) # the enabling code's time step is used
    click_on "Vérifier"

    assert_text "Connexion réussie."
    assert_selector ".sidebar .user-role", text: "Opérateur"
  end

  test "a mandatory 2FA opens its setup page at once; the backup codes can be downloaded" do
    AppSetting.current.update!(require_operator_two_factor: true)
    sign_in users(:operator)
    visit servers_path

    assert_selector "h1", text: "Activer la double authentification"
    assert_selector ".two-factor-mandatory", text: "obligatoire pour votre rôle (opérateur)"
    secret = find(".two-factor-secret").text.delete(" ")
    find("input[name=code]").fill_in(with: ROTP::TOTP.new(secret).now)
    click_on "Activer"

    assert_selector "textarea.backup-codes"
    # Catch the download instead of letting the browser save a file.
    execute_script(<<~JS)
      HTMLAnchorElement.prototype.click = function () { window.downloaded = [this.download, this.href.startsWith("blob:")] }
    JS
    click_on "Télécharger"
    assert_equal [ "elio-backup-codes-127.0.0.1.txt", true ], evaluate_script("window.downloaded")
    click_on "J'ai enregistré mes codes"
    assert_selector ".two-factor-state", text: "Activée"
  end

  test "an admin unlocks a locked account from the users page" do
    users(:operator).lock_access!
    sign_in users(:one)
    visit settings_users_path

    within "#user_#{users(:operator).id}" do
      assert_selector ".user-state", text: "Verrouillé"
      find("details.actions-menu summary").click
      click_on "Déverrouiller"
    end

    assert_text "operator@example.com peut de nouveau se connecter."
    assert_no_selector "#user_#{users(:operator).id} .user-state"
    assert_not users(:operator).reload.access_locked?
  end
end
