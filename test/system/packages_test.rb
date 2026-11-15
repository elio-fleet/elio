require "application_system_test_case"

class PackagesSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include PackageHelpers

  setup do
    record_packages(servers(:web), [ { manager: "dpkg", name: "openssl", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true } ])
    sign_in users(:viewer)
  end

  test "the security updates grouped by server, with the command to copy" do
    visit packages_path
    assert_selector "tr.security-update", text: "openssl"

    click_on "Par serveur"

    within ".server-updates", text: "Web" do
      assert_selector "pre.update-command", text: "sudo apt-get install --only-upgrade openssl"
      page.driver.browser.add_permission("clipboard-write", "granted")
      click_on "Copier"
      assert_text "Copié"
    end
    click_on "Par paquet"
    assert_selector "tr.security-update", text: "openssl"
  end
end
