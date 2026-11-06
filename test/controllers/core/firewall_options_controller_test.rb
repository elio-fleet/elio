require "test_helper"

class FirewallOptionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup { sign_in users(:one) }

  test "the options are in the Firewall tab of the settings, not in General" do
    get settings_path
    assert_select "#firewall-settings", 0
    assert_select "nav.settings-nav a[href=?]", settings_firewall_path, text: "Firewall"
    get settings_firewall_path
    assert_select "nav.settings-nav a[aria-current=page][href=?]", settings_firewall_path
    assert_select "#firewall-settings form.firewall-options" do
      assert_select "input[type=checkbox][name='app_setting[ufw_block_ipv6]']:not([checked])"
      assert_select "input[type=checkbox][name='app_setting[ovh_ipv6_health]']:not([checked])"
    end
  end

  test "saves the options; the health is computed again when the IPv6 reason changes" do
    refreshed = []
    stub_method(Server, :find_each, ->(&block) { refreshed << :all }) do
      patch settings_firewall_options_path, params: { app_setting: { ufw_block_ipv6: "1", ovh_ipv6_health: "0" } }
    end
    assert_redirected_to settings_firewall_path
    assert AppSetting.current.ufw_block_ipv6
    assert_empty refreshed

    stub_method(Server, :find_each, ->(&block) { refreshed << :all }) do
      patch settings_firewall_options_path, params: { app_setting: { ufw_block_ipv6: "1", ovh_ipv6_health: "1" } }
    end
    assert AppSetting.current.ovh_ipv6_health
    assert_equal [ :all ], refreshed
  end
end
