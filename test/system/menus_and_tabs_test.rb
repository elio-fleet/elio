require "application_system_test_case"

class MenusAndTabsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "the fleet actions are in a menu that closes on Escape and outside clicks" do
    visit servers_path
    assert_no_selector "#fleet-actions [role=menuitem]"
    find("#fleet-actions summary").click
    within("#fleet-actions [role=menu]") do
      assert_selector "[role=menuitem]", text: "Inventorier tout le parc"
      assert_selector "[role=menuitem]", text: "Scanner les clés de tout le parc"
      assert_selector "[role=menuitem]", text: "Importer des serveurs"
    end
    find("#fleet-actions summary").send_keys(:down)
    assert_equal "menuitem", evaluate_script("document.activeElement.getAttribute('role')")
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#fleet-actions [role=menuitem]"
    assert_equal "SUMMARY", evaluate_script("document.activeElement.tagName")

    find("#fleet-actions summary").click
    find("h1").click
    assert_no_selector "#fleet-actions [role=menuitem]"

    find("#fleet-actions summary").click
    click_on "Importer des serveurs"
    assert_selector "h1", text: "Importer"
  end

  test "tabs that do not fit go into a More menu, the current one stays visible" do
    page.driver.browser.manage.window.resize_to(820, 1000)
    visit server_path(servers(:web), tab: "journal")
    within("nav.server-tabs") do
      assert_selector ".tabs-more summary", text: "Plus"
      assert_selector ".tabs-bar > a[aria-current=page][data-tab=journal]"
      hidden = all(".tabs-bar > a[data-tab]", visible: :hidden).map { |link| link["data-tab"] }
      assert_not_empty hidden
      find(".tabs-more summary").click
      hidden.each { |tab| assert_selector "[role=menuitem][data-tab=#{tab}]" }
      first("[role=menuitem]").click
    end
    assert_no_selector "nav.server-tabs a[aria-current=page][data-tab=journal]"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "on a wide screen every tab is visible, in the new order" do
    visit server_path(servers(:web))
    assert_no_selector ".tabs-more summary"
    tabs = all("nav.server-tabs .tabs-bar > a[data-tab]").map { |link| link["data-tab"] }
    assert_equal %w[overview vulnerabilities packages services firewall schedules keys journal], tabs - %w[docker]
  end

  test "on a phone the tabs are a drop-down list" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
    visit server_path(servers(:web))
    assert_no_selector ".tabs-bar a[data-tab]"
    find("select.tabs-select").select "Firewall"
    assert_current_path server_path(servers(:web), tab: "firewall")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
