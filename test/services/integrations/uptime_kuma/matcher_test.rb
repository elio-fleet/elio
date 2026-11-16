require "test_helper"

class Integrations::UptimeKuma::MatcherTest < ActiveSupport::TestCase
  include StubHelpers

  Monitor = Integrations::UptimeKuma::Metrics::Monitor

  def monitor(id: "1", name: "Sonde", hostname: nil, url: nil, tags: [])
    Monitor.new(id:, name:, monitor_type: "ping", url:, hostname:, port: nil, tags:, status: 1, response_time_ms: nil, uptime: {},
                average_response_ms: {}, cert_days_remaining: nil, cert_valid: nil)
  end

  setup do
    servers(:web).update_columns(ip_addresses: [ "10.8.0.100", "2001:db8::10" ])
    servers(:db).inventory_snapshots.create!(category: "os", status: "ok", data: { "hostname" => "fr-utils-1.example.internal" },
                                              collected_at: Time.current, checked_at: Time.current)
  end

  def matcher(**options) = Integrations::UptimeKuma::Matcher.new(Server.includes(:inventory_snapshots).order(:name), **options)

  test "by an IP of the server (WireGuard address, IPv6 written differently)" do
    match = matcher.call(monitor(hostname: "10.8.0.100"))
    assert_equal [ servers(:web), "ip", "10.8.0.100" ], [ match.server, match.matched_by, match.address ]
    assert_equal servers(:web), matcher.call(monitor(hostname: "2001:0db8:0:0::10")).server
    assert_equal servers(:backup), matcher.call(monitor(hostname: "10.0.0.5")).server, "the SSH host"
    assert_nil matcher.call(monitor(hostname: "10.9.9.9"))
  end

  test "by the host of the URL: host name of the machine, its short name or the SSH host" do
    assert_equal [ servers(:db), "url" ], matcher.call(monitor(url: "https://fr-utils-1.example.internal/health")).then { [ _1.server, _1.matched_by ] }
    assert_equal servers(:db), matcher.call(monitor(hostname: "FR-UTILS-1")).server
    assert_equal servers(:db), matcher.call(monitor(url: "https://db.example.com:8443/")).server
    assert_equal servers(:web), matcher.call(monitor(url: "http://[2001:db8::10]/")).server
  end

  test "by DNS resolution, only when enabled" do
    stub_method(Resolv::DNS, :open, ->(*) { [ "10.8.0.100" ] }) do
      assert_nil matcher.call(monitor(url: "http://rproxy.example.tech/"))
      match = matcher(resolve_dns: true).call(monitor(url: "http://rproxy.example.tech/"))
      assert_equal [ servers(:web), "dns", "10.8.0.100" ], [ match.server, match.matched_by, match.address ]
    end
  end

  test "by the name of the probe, as a whole word, the longest name first" do
    Server.create!(name: "Web-2", host: "10.0.0.20", username: "root")
    assert_equal [ servers(:db), "name" ], matcher.call(monitor(name: "[SRV] [INTRANET] FR-UTILS-1")).then { [ _1.server, _1.matched_by ] }
    assert_equal "Web-2", matcher.call(monitor(name: "[SRV] Web-2 ping")).server.name
    assert_equal "Web", matcher.call(monitor(name: "Ping web")).server.name
    assert_nil matcher.call(monitor(name: "Website"))
  end

  test "each rule can be disabled" do
    off = matcher(by_ip: false, by_host: false, by_name: false)
    assert_nil off.call(monitor(name: "Web", hostname: "10.8.0.100", url: "https://db.example.com/"))
  end

  test "a manual link wins, even to no server" do
    manual = matcher(manual_links: { "7" => servers(:backup).id, "8" => nil })
    assert_equal [ servers(:backup), "manual" ], manual.call(monitor(id: "7", hostname: "10.8.0.100")).then { [ _1.server, _1.matched_by ] }
    assert_nil manual.call(monitor(id: "8", hostname: "10.8.0.100"))
  end

  test "by the tag naming the server: its name (even as Uptime Kuma writes it), host name or address; before the other rules" do
    Server.create!(name: "vm-db1", host: "10.0.0.31", username: "root")
    tagged = matcher(tag: "server")
    match = tagged.call(monitor(tags: [ "Prod", "server:vmdb1" ], hostname: "10.8.0.100"))
    assert_equal [ "vm-db1", "tag" ], [ match.server.name, match.matched_by ], "Uptime Kuma drops the dash; the tag wins over the IP"
    assert_equal servers(:db), tagged.call(monitor(tags: [ "Server:fr-utils-1" ])).server, "the tag name in any case, the host name of the server"
    assert_equal servers(:backup), tagged.call(monitor(tags: [ "server:unknown,10.0.0.5" ])).server, "several values, an address"
    assert_equal servers(:web), tagged.call(monitor(tags: [ "server:nowhere" ], hostname: "10.8.0.100")).server, "an unknown value leaves the other rules"
    assert_nil matcher.call(monitor(tags: [ "server:vmdb1" ])), "without the setting"
    assert_nil matcher(tag: "host").call(monitor(tags: [ "server:vmdb1" ]))
  end

  test "explains why a probe matches no server" do
    explain = ->(probe, **options) { matcher(**options).explain(probe).values_at("key", "params") }

    assert_equal [ "manual_none", {} ], matcher(manual_links: { "8" => nil }).explain(monitor(id: "8", hostname: "10.8.0.100")).values_at("key", "params")
    assert_equal [ "unknown_tag", { "tag" => "nowhere" } ], explain.(monitor(tags: [ "server:nowhere" ], hostname: "10.9.9.9"), tag: "server")
    assert_equal [ "no_target", {} ], explain.(monitor(name: "Push backup"))
    assert_equal [ "no_target_name_off", {} ], explain.(monitor(name: "Push backup"), by_name: false)
    assert_equal [ "unknown_ip", { "address" => "10.9.9.9" } ], explain.(monitor(hostname: "10.9.9.9"))
    assert_equal [ "ip_off", { "address" => "10.8.0.100" } ], explain.(monitor(hostname: "10.8.0.100"), by_ip: false)
    assert_equal [ "host_off", { "host" => "app.example.com" } ], explain.(monitor(url: "https://app.example.com/"), by_host: false)
    assert_equal [ "host_no_dns", { "host" => "app.example.com" } ], explain.(monitor(url: "https://app.example.com/"))

    stub_method(Resolv::DNS, :open, ->(*) { [ "198.51.100.7" ] }) do
      assert_equal [ "resolved_elsewhere", { "host" => "app.example.com", "addresses" => "198.51.100.7" } ], explain.(monitor(url: "https://app.example.com/"), resolve_dns: true)
    end
    stub_method(Resolv::DNS, :open, ->(*) { [] }) do
      assert_equal [ "not_resolved", { "host" => "app.example.com" } ], explain.(monitor(url: "https://app.example.com/"), resolve_dns: true)
    end
  end
end
