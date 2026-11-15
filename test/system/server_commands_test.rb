require "application_system_test_case"

class ServerCommandsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include TcpHelpers

  setup do
    Server.update_all(host: "127.0.0.1", port: closed_port)
    sign_in users(:one)
  end

  test "the commands Elio runs are reachable from the server's menu" do
    visit server_path(servers(:web))
    find("#server-actions summary").click
    click_on "Commandes lancées par Elio"

    assert_selector "h1", text: "Commandes lancées par Elio"
    assert_selector "#commands-inventory .server-command", minimum: 1
    within("#command-keys-append") { assert_selector ".command-writes", text: "Peut écrire" }
    within("#command-inventory-os") { assert_no_selector ".command-writes" }
    click_on "Web"
    assert_selector "h1", text: "Web"
  end

  test "the page fits a phone" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 800, deviceScaleFactor: 1, mobile: true)
    visit server_commands_path(servers(:web))
    assert_selector "h1", text: "Commandes lancées par Elio"
    assert_not evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
