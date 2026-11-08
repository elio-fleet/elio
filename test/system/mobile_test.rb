require "application_system_test_case"

# On a phone, no page scrolls sideways (wide tables scroll inside their card)
# and the sidebar is a drawer.
class MobileTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  setup do
    sign_in users(:one)
    record_ports(servers(:web))
    # A true phone width, emulated: a resized window keeps at least 500 px on
    # macOS but not on Linux, so the test would not check the same thing everywhere.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  test "no page is wider than the screen" do
    [ root_path, servers_path, servers_path(view: "grid"), server_path(servers(:web)), server_path(servers(:web), tab: "keys"), server_path(servers(:web), tab: "firewall"),
      ports_path, packages_path, public_keys_path, activities_path, tasks_path, settings_automations_path, settings_users_path,
      scheduled_tasks_path, vulnerabilities_path, settings_vulnerabilities_path, docker_path, settings_docker_path, new_settings_score_provider_path,
      server_path(servers(:web), tab: "vulnerabilities") ].each do |path|
      visit path
      assert_selector "h1"
      overflow = evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
      assert_operator overflow, :<=, 0, "#{path} scrolls sideways by #{overflow} px"
    end
  end

  test "the sidebar opens as a drawer" do
    visit root_path
    assert_no_selector "nav.main-nav a", text: "Serveurs" # off screen
    find("button[aria-label='Ouvrir le menu']").click
    within("nav.main-nav") { click_on "Journal" }
    assert_selector "h1", text: "Journal"
  end
end
