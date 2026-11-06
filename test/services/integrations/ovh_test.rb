require "test_helper"

class Integrations::OvhTest < ActiveSupport::TestCase
  include StubHelpers
  include OvhHelpers

  setup do
    servers(:web).update_columns(ip_addresses: [ "203.0.113.10", "10.8.0.10" ])
    servers(:web).inventory_snapshots.create!(category: "os", status: "ok", data: { "hostname" => "web.example.com" }, collected_at: Time.current, checked_at: Time.current)
    @integration = enable_ovh
  end

  test "registered, with its automation" do
    assert_equal "Integrations::Ovh", Integration.registry["ovh"]
    assert Automation.all_kinds.find { |automation| automation.kind == "ovh_sync" }.available?
  end

  test "fetch reads every chosen product" do
    fake_ovh
    resources = Integrations::Ovh::Fetch.new(Integrations::Ovh.client(@integration), products: Integrations::Ovh::Fetch::PRODUCTS).call
    by_kind = resources.group_by(&:kind)

    assert_equal %w[dedicated dns_record instance ip vps], by_kind.keys.sort
    block = by_kind["ip"].find { |resource| resource.name == "203.0.113.10/32" }
    assert_equal({ "203.0.113.10" => "web.example.com" }, block.data["reverse"])
    assert_equal [ 0, 1, 19 ], block.data.dig("firewall", "203.0.113.10", "rules").map { _1["sequence"] }
    assert_equal true, block.data.dig("mitigation", "203.0.113.10", "auto")
    assert_equal [ "www.example.com", "old.example.com", "app.example.com" ], by_kind["dns_record"].map(&:name)
    assert_equal [ "203.0.113.10" ], by_kind["dns_record"].first.addresses
    assert_equal [], by_kind["dns_record"].last.addresses, "a CNAME has no address"
    dedicated = by_kind["dedicated"].sole
    assert_equal [ "web.example.com", "Advance-1", "gra3", false ], [ dedicated.name, *dedicated.data.values_at("offer", "datacenter", "renew_automatic") ]
    assert_equal 10.days.from_now.to_date, dedicated.expires_at
    assert_equal [ "10.1.2.3", "192.0.2.50" ], by_kind["instance"].sole.addresses
  end

  test "fetch only what is chosen, and only the chosen zones" do
    fake_ovh
    resources = Integrations::Ovh::Fetch.new(Integrations::Ovh.client(@integration), products: %w[dns], zones: %w[other.com]).call
    assert_empty resources
    assert(@ovh_requests.none? { |url, _| url.include?("/ip") || url.include?("/vps") })
  end

  test "sync attaches the resources to the servers" do
    fake_ovh
    summary = @integration.sync!
    assert_equal "1 instance, 1 dédié, 1 VPS, 2 blocs IP, 3 enregistrements DNS ; 1 service non rattaché", summary

    find = ->(kind, name) { OvhResource.find_by!(kind: kind, name: name) }
    assert_equal [ servers(:web), "address", "203.0.113.10" ], find.("dedicated", "web.example.com").then { [ _1.server, _1.matched_by, _1.matched_address ] }
    assert_equal [ servers(:web), "address" ], find.("ip", "203.0.113.10/32").then { [ _1.server, _1.matched_by ] }
    dns = ->(name) { DnsRecord.of_source("ovh").find_by!(name: name) }
    assert_equal [ servers(:web), "address" ], dns.("www.example.com").then { [ _1.server, _1.matched_by ] }
    assert_equal [ servers(:web), "cname" ], dns.("app.example.com").then { [ _1.server, _1.matched_by ] }
    assert_nil dns.("old.example.com").server
    assert_not OvhResource.exists?(kind: "dns_record"), "the DNS records are in the DNS of the fleet"
    assert_equal [ servers(:db), "name" ], find.("instance", "Database").then { [ _1.server, _1.matched_by ] }
    assert_nil find.("vps", "Staging").server
    assert_nil find.("ip", "198.51.100.7/32").server
  end

  test "an IP block routed to an attached service, and manual links" do
    routes = ovh_account
    routes["/ip"] << "198.51.100.8/32"
    routes["/ip/198.51.100.8%2F32"] = { "ip" => "198.51.100.8/32", "type" => "failover", "routedTo" => { "serviceName" => "ns1234.ip-203-0-113.eu" } }
    %w[reverse firewall mitigation].each { |part| routes["/ip/198.51.100.8%2F32/#{part}"] = [] }
    fake_ovh(routes)
    @integration.links.create!(external_id: "vps:vps-abc123.vps.ovh.net", server: servers(:backup))
    @integration.links.create!(external_id: "instance:p1/i-1", server: nil)
    @integration.sync!

    assert_equal [ servers(:web), "service" ], OvhResource.find_by!(name: "198.51.100.8/32").then { [ _1.server, _1.matched_by ] }
    assert_equal [ servers(:backup), "manual" ], OvhResource.find_by!(kind: "vps").then { [ _1.server, _1.matched_by ] }
    assert_nil OvhResource.find_by!(kind: "instance").server
  end

  test "resources gone from OVH are removed" do
    fake_ovh
    @integration.sync!
    routes = ovh_account
    routes["/cloud/project/p1/instance"] = []
    fake_ovh(routes)
    @integration.sync!
    assert_not OvhResource.exists?(kind: "instance")
  end

  test "alerts: each once, never on the first sync, only when enabled" do
    @integration.update!(settings: @integration.settings.merge("alert_unmanaged_service" => true))
    AppSetting.current.update!(dns_alert_outside: true)
    fake_ovh
    @integration.sync!
    assert_equal 0, Activity.where(kind: %w[ovh_service_expiring dns_record_outside_fleet ovh_service_unmanaged]).count

    routes = ovh_account
    routes["/domain/zone/example.com/record?fieldType=A"] = [ 1, 2, 4 ]
    routes["/domain/zone/example.com/record/4"] = { "fieldType" => "A", "subDomain" => "legacy", "target" => "192.0.2.100", "ttl" => 0 }
    fake_ovh(routes)
    2.times { @integration.reload.sync! }
    assert_equal [ "legacy.example.com pointe vers 192.0.2.100, hors du parc" ], Activity.of_kind(:dns_record_outside_fleet).map(&:summary)
    assert_equal 0, Activity.of_kind(:ovh_service_expiring).count, "already expiring at the first sync"
  end

  test "an expiring service is logged when it enters the window" do
    fake_ovh(ovh_account(expiration: 90.days.from_now.to_date))
    @integration.sync!
    fake_ovh(ovh_account(expiration: 20.days.from_now.to_date))
    @integration.reload.sync!
    assert_equal [ "Service OVH « web.example.com » : expire dans 20 jours" ], Activity.of_kind(:ovh_service_expiring).map(&:summary)
  end

  test "health reasons, each alert enabled in the settings" do
    fake_ovh
    @integration.sync!
    reasons = -> { Integrations::Ovh.health_reasons(@integration.reload, servers(:web).reload).map { [ _1.tone, _1.text ] } }
    assert_equal [ [ "warn", "Service OVH « web.example.com » : expire dans 10 j" ] ], reasons.call

    @integration.update!(settings: @integration.settings.merge("expiring_ignore_auto_renew" => true, "alert_firewall_disabled" => true,
                                                                 "alert_reverse_mismatch" => true))
    assert_equal 1, reasons.call.size, "firewall on, reverse = host name, DNS records exist"

    fake_ovh(ovh_account(renew_automatic: true).merge("/ip/203.0.113.10%2F32/firewall/203.0.113.10" => { "enabled" => false },
                                                      "/ip/203.0.113.10%2F32/reverse/203.0.113.10" => { "reverse" => "ns1234.ip-203-0-113.eu." },
                                                      "/domain/zone/example.com/record?fieldType=A" => [ 2 ], "/domain/zone/example.com/record?fieldType=CNAME" => []))
    @integration.sync!
    assert_equal [ [ "warn", "Firewall réseau OVH désactivé sur 203.0.113.10" ], [ "warn", "Reverse DNS de 203.0.113.10 (ns1234.ip-203-0-113.eu) ≠ hostname" ] ], reasons.call
  end

  test "test_connection checks the rights: missing ones, and a key that could write" do
    fake_ovh
    assert_equal "clé valide (validated)", Integrations::Ovh.test_connection(@integration)

    routes = ovh_account
    routes["/auth/currentCredential"] = { "status" => "validated", "rules" => [ { "method" => "GET", "path" => "/ip*" }, { "method" => "DELETE", "path" => "/ip/*" } ] }
    fake_ovh(routes)
    message = Integrations::Ovh.test_connection(@integration)
    assert_match "Droits manquants : GET /auth/currentCredential, GET /domain/zone", message
    assert_match "⚠ Cette clé permet aussi d'écrire (DELETE /ip/*)", message
  end

  test "rights and the prefilled token page follow the chosen products" do
    @integration.update!(settings: @integration.settings.merge("products" => %w[dns vps], "endpoint" => "ovh-ca"))
    assert_equal %w[/auth/currentCredential /domain/zone /domain/zone/* /vps /vps/*], Integrations::Ovh.rights(@integration)
    assert_equal "https://ca.api.ovh.com/createToken/?GET=/auth/currentCredential&GET=/domain/zone&GET=/domain/zone/*&GET=/vps&GET=/vps/*",
                 Integrations::Ovh.token_url(@integration)
  end
end
