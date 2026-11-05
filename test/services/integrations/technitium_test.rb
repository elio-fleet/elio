require "test_helper"

class Integrations::TechnitiumTest < ActiveSupport::TestCase
  include StubHelpers
  include TechnitiumHelpers

  setup do
    @integration = enable_technitium
    fake_technitium
    servers(:web).update!(extra_addresses_text: "203.0.113.10, 2001:db8::10")
    servers(:db).update!(extra_addresses_text: "10.0.0.12")
  end

  def sync = Integrations::Technitium.sync(@integration.reload)

  test "reads with GET and a Bearer token, never the token in the URL" do
    sync
    assert @technitium_requests.any?
    @technitium_requests.each do |url, options|
      assert_not_includes url, "tt-token"
      assert_equal "Bearer tt-token", options.dig(:headers, "Authorization")
      assert url.start_with?("#{TechnitiumHelpers::URL}/api/")
    end
    assert_equal [ "example.test", "internal.test" ], @technitium_requests.filter_map { |url, _| URI.decode_www_form(URI(url).query.to_s).to_h["zone"] }
  end

  test "stores the A, AAAA and CNAME records, attached by IP, by CNAME, and outside the fleet" do
    summary = sync

    assert_equal "2 zones, 7 enregistrements, 3 rattachés à aucun serveur", summary
    rows = DnsRecord.order(:name, :record_type).map { |record| [ record.name, record.record_type, record.value, record.server&.name, record.matched_by ] }
    assert_equal [
      [ "old.example.test", "A", "198.51.100.99", nil, nil ],
      [ "shop.example.test", "CNAME", "cdn.provider.example", nil, nil ],
      [ "web.example.test", "A", "203.0.113.10", "Web", "address" ],
      [ "web.example.test", "AAAA", "2001:db8::10", "Web", "address" ],
      [ "www.example.test", "CNAME", "web.example.test", "Web", "cname" ],
      [ "db.internal.test", "A", "10.0.0.12", "Database", "address" ],
      [ "vpn.internal.test", "A", "10.8.0.100", nil, nil ]
    ].sort_by { |name, type, *| [ name, type ] }, rows
    assert_equal [ "old.example.test", "vpn.internal.test" ], DnsRecord.outside_fleet.order(:name).pluck(:name)
    assert_not DnsRecord.exists?(record_type: %w[SOA NS])
  end

  test "only the zones chosen, and a sync replaces the records" do
    @integration.update!(settings: @integration.settings.merge("zones" => [ "internal.test" ]))
    sync
    assert_equal [ "internal.test" ], DnsRecord.distinct.pluck(:zone)

    @integration.update!(settings: @integration.settings.merge("zones" => []))
    fake_technitium("/api/zones/list" => { "response" => { "zones" => [ { "name" => "example.test" } ] }, "status" => "ok" }.to_json)
    sync
    assert_equal [ "example.test" ], DnsRecord.distinct.pluck(:zone)
  end

  test "a manual link wins, by name, and stays across syncs" do
    DnsLink.create!(name: "vpn.internal.test", server: servers(:backup))
    DnsLink.create!(name: "web.example.test", server: nil)
    sync
    assert_equal "Backup", DnsRecord.find_by!(name: "vpn.internal.test").server.name
    assert_equal [ nil, nil ], DnsRecord.where(name: "web.example.test").pluck(:server_id)
  end

  test "outside-the-fleet records are logged once, not on the first sync, when the alert is on" do
    @integration.update!(settings: @integration.settings.merge("alert_outside" => true))
    assert_no_difference -> { Activity.of_kind(:dns_record_outside_fleet).count } do
      sync
    end
    servers(:db).update!(extra_addresses_text: "")
    assert_difference -> { Activity.of_kind(:dns_record_outside_fleet).count }, 1 do
      sync
    end
    assert_equal "db.internal.test pointe vers 10.0.0.12, hors du parc", Activity.of_kind(:dns_record_outside_fleet).last.summary
    assert_no_difference -> { Activity.of_kind(:dns_record_outside_fleet).count } do
      sync
    end
  end

  test "servers without a DNS name get a warning when the alert is on" do
    sync
    @integration.update!(last_synced_at: Time.current, settings: @integration.settings.merge("alert_server_without_dns" => true))
    assert_equal [ "Aucun nom DNS dans Technitium" ], Integrations::Technitium.health_reasons(@integration, servers(:backup)).map { |reason| Inventory::HealthStatus.text(reason.to_h.stringify_keys) }
    assert_empty Integrations::Technitium.health_reasons(@integration, servers(:web))
  end

  test "test the connection: version, zones, a warning when the token can write" do
    assert_equal "Connecté à Technitium DNS Server 15.6.2 : 2 zones lisibles", Integrations::Technitium.test_connection(@integration)

    session = JSON.parse(file_fixture("integrations/technitium/session_get.json").read)
    session["info"]["permissions"]["Zones"]["canModify"] = true
    fake_technitium("/api/user/session/get" => session.to_json)
    assert_match "ce jeton peut aussi modifier", Integrations::Technitium.test_connection(@integration)
  end

  test "errors are readable: invalid token, access denied, not Technitium" do
    fake_technitium("/api/zones/list" => file_fixture("integrations/technitium/invalid_token.json").read)
    error = assert_raises(Integrations::Error) { sync }
    assert_match "Jeton invalide", error.message

    fake_technitium("/api/zones/list" => { status: "error", errorMessage: "Access was denied." }.to_json)
    assert_match "Access was denied.", assert_raises(Integrations::Error) { sync }.message

    fake_technitium("/api/zones/list" => "<html>")
    assert_match "Réponse inattendue", assert_raises(Integrations::Error) { sync }.message
  end

  test "Uptime Kuma attaches a probe by a Technitium name, and the monitors prompt lists the names" do
    sync
    monitor = Integrations::UptimeKuma::Metrics.parse(%(monitor_status{monitor_id="9",monitor_name="Shop",monitor_type="http",monitor_url="https://www.example.test/",monitor_hostname="null",monitor_port="null"} 1\n)).monitors.sole
    match = Integrations::UptimeKuma::Matcher.new(Server.all, by_name: false).call(monitor)
    assert_equal [ servers(:web), "dns_record" ], [ match.server, match.matched_by ]

    text = ServerPrompt.new(servers(:web)).monitors
    assert_includes text, "## Noms DNS qui pointent vers lui\n- web.example.test (A 203.0.113.10, Technitium)\n- web.example.test (AAAA 2001:db8::10, Technitium)\n- www.example.test (CNAME web.example.test, Technitium)"
  end
end
