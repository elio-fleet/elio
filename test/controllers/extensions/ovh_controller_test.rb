require "test_helper"

class OvhControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include StubHelpers
  include OvhHelpers
  include PortHelpers

  setup do
    sign_in users(:one)
    servers(:web).update_columns(ip_addresses: [ "203.0.113.10" ])
    servers(:web).inventory_snapshots.create!(category: "os", status: "ok", data: { "hostname" => "web.example.com" }, collected_at: Time.current, checked_at: Time.current)
    @integration = enable_ovh
    fake_ovh
    @integration.sync!
  end

  test "404 while disabled, and no trace" do
    @integration.update!(enabled: false)
    get ovh_path
    assert_response :not_found

    sign_in users(:one)
    get server_path(servers(:web), tab: "ovh")
    assert_select "nav.server-tabs a[data-tab=ovh]", 0
    assert_select "nav.main-nav a", text: "OVHcloud", count: 0
  end

  test "the services tab, for every role" do
    sign_in users(:viewer)
    get ovh_path

    assert_select "nav.main-nav a[data-integration-link][aria-current=page]", "OVHcloud"
    assert_select "#stat-ovh-services .stat-value", "3"
    assert_select "#stat-ovh-unattached .stat-value", "1"
    assert_select "#stat-ovh-expiring .stat-value", "1"
    assert_select "#stat-ovh-dns-outside .stat-value", "1"
    assert_select "tr.ovh-resource", 3
    assert_select "tr.ovh-resource[data-kind=dedicated] .ovh-server a[href=?]", server_path(servers(:web), tab: "ovh"), text: "Web"
    assert_select "tr.ovh-resource[data-kind=dedicated] .ovh-expiration", text: /\d{4}/
    assert_select "form.ovh-link-form", 0
  end

  test "IP and DNS tabs, filters" do
    get ovh_path(tab: "ips")
    assert_select "tr.ovh-resource[data-kind=ip]", 2

    get ovh_path(tab: "dns", unattached: "1")
    assert_select "tr.ovh-resource", 1
    assert_select "tr.ovh-resource", text: /old\.example\.com.*hors du parc/m

    get ovh_path(tab: "services", q: "staging")
    assert_select "tr.ovh-resource", 1
  end

  test "the server tab: service, IP with reverse, firewall rules and their effect on the public ports, DNS records" do
    record_ports(servers(:web))
    get server_path(servers(:web), tab: "ovh")

    assert_select "nav.server-tabs a[data-tab=ovh][aria-current=page]", text: /OVH/
    assert_select ".ovh-service", text: /Serveur dédié · web\.example\.com.*Advance-1.*gra3/m
    assert_select ".ovh-ip[data-block='203.0.113.10/32'] .ovh-reverse", "web.example.com"
    assert_select ".ovh-firewall-rule", 3
    assert_select ".ovh-firewall-rule", text: "0 autoriser tcp eq 22 depuis 192.0.2.0/24"
    assert_select ".ovh-port[data-port='22/tcp'] .ovh-firewall-verdict", "OVH : sources limitées"
    assert_select ".ovh-port[data-port='9100/tcp'] .ovh-firewall-verdict", "OVH : bloqué"
    assert_select ".ovh-mitigation", text: /automatique/
    assert_select "tr.ovh-dns-record", 2
  end

  test "attach a service by hand, back to automatic through a sync" do
    vps = OvhResource.find_by!(kind: "vps")
    post ovh_resource_link_path(vps), params: { server_id: servers(:backup).id }
    assert_equal [ servers(:backup), "manual" ], vps.reload.then { [ _1.server, _1.matched_by ] }

    @integration.reload.sync!
    assert_equal servers(:backup), vps.reload.server

    delete ovh_resource_link_path(vps)
    assert_empty @integration.links.reload
    assert_redirected_to task_path(BackgroundTask.recent.first)
  end

  test "attaching is for operators" do
    sign_in users(:viewer)
    post ovh_resource_link_path(OvhResource.first), params: { server_id: servers(:db).id }
    assert_response :forbidden
  end

  test "the settings page explains the rights of the API key, with the prefilled token page" do
    get edit_settings_integration_path("ovh")
    assert_select ".ovh-rights-button", text: /Droits à donner à la clé API/
    assert_select "dialog.ovh-rights .ovh-rights-list", text: %r{GET /ip/\*}
    assert_select "dialog.ovh-rights a.ovh-token-link[href^='https://eu.api.ovh.com/createToken/?GET=/auth/currentCredential']"
    assert_select "input[type=checkbox][name='integration[values][products][]']", 7
    assert_select "input[type=password][name='integration[values][application_secret]']:not([value])"
    assert_not_includes response.body, "app-secret"
  end

  test "the OVH tab offers a prompt for the network firewall rules" do
    record_ports(servers(:web))
    get server_path(servers(:web), tab: "ovh")
    assert_select "#server-ovh .server-prompt[data-kind=ovh_firewall]" do
      assert_select "button.server-prompt-button", /Prompt pour proposer des règles de firewall/
      assert_select "dialog textarea.server-prompt-text", /hébergé chez OVHcloud.*203\.0\.113\.10.*n°\d+ (permit|deny)/m
    end
  end
end
