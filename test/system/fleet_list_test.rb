require "application_system_test_case"

# The fleet table in a browser: it fits its card on a desktop screen (the
# last column was cut at 1,400 px), its columns are chosen by the user and
# a click on a header sorts it.
class FleetListTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    long_reason = { "tone" => "warn", "text" => "Aucune sonde Uptime Kuma ne surveille ce serveur depuis son ajout dans Elio" }
    Server.find_each do |server|
      server.update_columns(health_status: "warn", health_reasons: [ long_reason, long_reason ], os_name: "Ubuntu 24.04.1 LTS", username: "deployment-user-#{server.id}")
      server.inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                         data: { "load_percent" => 10 + server.id % 50, "memory" => { "used_percent" => 88 }, "disk_max_percent" => 20 + server.id % 70,
                                                 "updates" => { "total" => 12, "security" => 4 } })
    end
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  [ 1280, 1400 ].each do |width|
    test "at #{width} px the table fits its card, its last column included" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: false)
      visit servers_path

      assert_selector "#servers .server-notes", text: /Aucune sonde/
      overflow = evaluate_script("document.querySelector('#servers').scrollWidth - document.querySelector('#servers').parentElement.clientWidth")
      assert_operator overflow, :<=, 0, "the table is cut by #{overflow} px"
      assert_selector "#servers tbody tr:first-child a[href$='/edit']", visible: true
    end
  end

  test "hiding a column keeps the filters, and the choice stays for the account" do
    visit servers_path(state: "warn")
    assert_selector "#servers th", text: /Charge 24 h/i

    find("#fleet-columns summary").click
    uncheck "Charge 24 h"
    click_on "Appliquer"

    assert_no_selector "#servers .server-load"
    assert_current_path servers_path(state: "warn")
    assert_selector "#servers .server-disk", count: 2 # Database does not answer
    assert_equal %w[load], users(:one).reload.hidden_fleet_columns
  end

  test "a click on a header sorts the list, a second one reverses it" do
    visit servers_path
    expected = Server.all.sort_by { |server| -(20 + server.id % 70) }.map(&:name)

    click_on "Disque"
    assert_selector "#servers th[aria-sort=descending]", text: /Disque/i
    assert_equal expected, all("#servers tbody tr td:nth-child(2) > a").map(&:text)

    click_on "Disque"
    assert_selector "#servers th[aria-sort=ascending]", text: /Disque/i
    assert_equal expected.reverse, all("#servers tbody tr td:nth-child(2) > a").map(&:text)
  end
end
