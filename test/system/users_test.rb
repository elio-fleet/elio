require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "an admin deactivates then reactivates an account from the same menu" do
    sign_in users(:one)
    visit settings_users_path

    find("summary[aria-label='Actions de viewer@example.com']").click
    accept_app_confirm { click_on "Désactiver" }

    assert_text "viewer@example.com est désactivé : il ne peut plus se connecter."
    assert_selector "#users .user-row.is-deactivated", text: "viewer@example.com"

    find("summary[aria-label='Actions de viewer@example.com']").click
    click_on "Réactiver"

    assert_text "viewer@example.com peut de nouveau se connecter."
    assert_no_selector "#users .user-row.is-deactivated"
  end
end
