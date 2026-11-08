require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "generating the first SSH key from the settings page" do
    SshKey.delete_all
    visit root_path
    assert_selector "#onboarding-ssh_key:not(.is-done)"

    find("nav a[title='Paramètres']").click
    click_on "Générer une clé SSH"

    assert_text "Clé SSH générée."
    assert_field "ssh-public-key", with: SshKey.current.public_key
  end

  test "regenerating asks for confirmation" do
    visit settings_path
    old_key = SshKey.current.public_key

    find("#ssh-key-actions summary").click
    dismiss_app_confirm { click_on "Régénérer la clé" }
    assert_field "ssh-public-key", with: old_key

    find("#ssh-key-actions summary").click unless page.has_selector?("#ssh-key-actions[open]", wait: 0)
    accept_app_confirm { click_on "Régénérer la clé" }
    assert_text "Nouvelle clé SSH générée."
    assert_no_field "ssh-public-key", with: old_key
  end

  test "copy button confirms the copy" do
    visit settings_path
    page.driver.browser.add_permission("clipboard-write", "granted")

    within("[data-controller=clipboard]", match: :first) do
      click_on "Copier"
      assert_text "Copié"
    end
  end
end
