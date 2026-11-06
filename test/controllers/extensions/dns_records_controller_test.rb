require "test_helper"

class DnsRecordsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include TechnitiumHelpers

  setup do
    @integration = enable_technitium
    fake_technitium
    servers(:web).update!(extra_addresses_text: "203.0.113.10")
    @integration.sync!
  end

  test "404 while disabled, and no trace" do
    @integration.update!(enabled: false)
    sign_in users(:one)
    get dns_records_path
    assert_response :not_found
    sign_in users(:one)
    get server_path(servers(:web))
    assert_select "nav.server-tabs a[data-tab=dns]", 0
  end

  test "the DNS page lists the records, filters, and the server tab, for every role" do
    sign_in users(:viewer)
    get dns_records_path
    assert_response :success
    assert_select "nav.main-nav a[data-integration-link][aria-current=page]", "DNS"
    assert_select ".dns-sources li[data-source=technitium]"
    assert_select "tr.dns-record[data-source=technitium] .dns-source", "Technitium"
    assert_select "#stat-dns-records .stat-value", "7"
    assert_select "#stat-dns-outside .stat-value", "4"
    assert_select "tr.dns-record[data-name='web.example.test'][data-type=A]", text: /Web.*par son IP 203\.0\.113\.10/m
    assert_select "tr.dns-record[data-name='old.example.test'] .dns-outside", "hors du parc"
    assert_select "form.technitium-link-form", 0

    get dns_records_path(filter: "outside")
    assert_select "tr.dns-record", 4
    get dns_records_path(zone: "internal.test", q: "vpn")
    assert_select "tr.dns-record", 1

    get server_path(servers(:web), tab: "dns")
    assert_select "nav.server-tabs a[data-tab=dns][aria-current=page]", text: /DNS\s*2/
    assert_select "#server-dns tr.dns-record", 2
  end

  test "an operator attaches a name by hand, then goes back to automatic" do
    sign_in users(:operator)
    record = DnsRecord.find_by!(name: "old.example.test")
    post dns_record_link_path(record), params: { server_id: servers(:backup).id }
    assert_equal servers(:backup), record.reload.server
    assert_equal "manual", record.matched_by
    assert_equal servers(:backup).id, DnsLink.find_by!(name: "old.example.test").server_id

    delete dns_record_link_path(record)
    assert_not DnsLink.exists?(name: "old.example.test")
    assert_nil record.reload.server, "back to automatic: its IP is outside the fleet"

    sign_in users(:viewer)
    post dns_record_link_path(record), params: { server_id: servers(:web).id }
    assert_response :forbidden
  end

  test "the settings page offers the extension with its help" do
    sign_in users(:one)
    get edit_settings_integration_path("technitium")
    assert_response :success
    assert_select "input[name='integration[values][url]']"
    assert_select "input[type=password][name='integration[values][api_token]']"
    assert_select ".integration-help", /droits par zone/
  end
end
