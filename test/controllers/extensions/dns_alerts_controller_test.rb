require "test_helper"

class DnsAlertsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" }) }

  test "the DNS section appears with a DNS source, and saves the common alerts" do
    sign_in users(:one)
    get settings_integrations_path
    assert_select "#dns-alerts form[action=?]", settings_dns_alerts_path do
      assert_select "input[type=checkbox][name='dns_alerts[outside]']"
      assert_select "input[type=checkbox][name='dns_alerts[without_name]']"
      assert_select "input[type=checkbox][name='dns_alerts[conflict]']"
      assert_select "input[name='dns_alerts[ignored_group_ids][]'][value=?]", server_groups(:staging).id.to_s
    end

    patch settings_dns_alerts_path, params: { dns_alerts: { outside: "1", without_name: "1", conflict: "0", ignored_group_ids: [ "", server_groups(:staging).id.to_s, "999999" ] } }
    assert_redirected_to settings_integrations_path(anchor: "dns-alerts")
    settings = AppSetting.current.reload
    assert_equal [ true, true, false, [ server_groups(:staging).id ] ],
                 [ settings.dns_alert_outside, settings.dns_alert_without_name, settings.dns_alert_conflict, settings.dns_without_name_ignored_group_ids ]
  end

  test "no DNS section without a DNS source; administrators only" do
    Integration.find_by!(kind: "technitium").update!(enabled: false)
    sign_in users(:one)
    get settings_integrations_path
    assert_select "#dns-alerts", 0

    sign_in users(:operator)
    patch settings_dns_alerts_path, params: { dns_alerts: { outside: "1" } }
    assert_response :forbidden
  end
end
