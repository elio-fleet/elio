require "test_helper"

# The DNS of the fleet, fed by several sources (phase 14).
class Dns::StoreTest < ActiveSupport::TestCase
  include IntegrationHelpers

  setup do
    enable_dns_sources(:ovh, :technitium)
    servers(:web).update!(extra_addresses_text: "203.0.113.10")
    servers(:db).update!(extra_addresses_text: "10.0.0.12")
  end

  def row(name, type, value, zone: "example.test") = { zone: zone, name: name, record_type: type, value: value }

  def names(source) = DnsRecord.of_source(source).order(:name).pluck(:name)

  test "a source replaces only its own records, normalized, A / AAAA / CNAME only" do
    assert_equal 2, Dns::Store.replace("ovh", [ row("WWW.example.test.", "A", "203.0.113.10"), row("mail.example.test", "MX", "mx"), row("app.example.test", "cname", "WWW.example.test.") ])
    Dns::Store.replace("technitium", [ row("db.lan.test", "A", "10.0.0.12", zone: "lan.test") ])
    assert_equal %w[app.example.test www.example.test], names("ovh")

    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10") ])
    assert_equal %w[www.example.test], names("ovh")
    assert_equal %w[db.lan.test], names("technitium"), "the other source is left alone"
    assert_equal "www.example.test", DnsRecord.find_by!(record_type: "A", source: "ovh").name
  end

  test "only the difference is written: an unchanged record keeps its row, a changed one is updated, a gone one deleted" do
    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10"), row("old.example.test", "A", "203.0.113.11"),
                                { zone: "example.test", name: "api.example.test", record_type: "A", value: "203.0.113.12", ttl: 300, source_id: "42" } ])
    www, api = DnsRecord.find_by!(name: "www.example.test"), DnsRecord.find_by!(name: "api.example.test")
    www.update_columns(updated_at: 1.day.ago)
    api.update_columns(updated_at: 1.day.ago)

    assert_equal 3, Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10"), row("new.example.test", "A", "203.0.113.13"),
                                                { zone: "example.test", name: "api.example.test", record_type: "A", value: "203.0.113.14", ttl: "600", source_id: "42" } ])
    assert_equal %w[api.example.test new.example.test www.example.test], names("ovh")
    assert_equal www.updated_at, www.reload.updated_at, "unchanged: not written"
    assert_equal [ api.id, "203.0.113.14", 600 ], api.reload.then { [ _1.id, _1.value, _1.ttl ] }, "changed in place"
    assert api.updated_at > 1.minute.ago
    assert_equal servers(:web), www.server, "still attached"
  end

  test "attached by IP, and a CNAME of one source follows a name of the other" do
    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10") ])
    Dns::Store.replace("technitium", [ row("intranet.lan.test", "CNAME", "www.example.test", zone: "lan.test"), row("db.lan.test", "A", "10.0.0.12", zone: "lan.test") ])

    assert_equal [ servers(:web), "address", "203.0.113.10" ], DnsRecord.find_by!(name: "www.example.test").then { [ _1.server, _1.matched_by, _1.matched_address ] }
    assert_equal [ servers(:web), "cname" ], DnsRecord.find_by!(name: "intranet.lan.test").then { [ _1.server, _1.matched_by ] }
    assert_equal servers(:db), DnsRecord.find_by!(name: "db.lan.test").server

    Dns::Store.replace("ovh", [])
    assert_nil DnsRecord.find_by!(name: "intranet.lan.test").server, "its target is gone"
  end

  test "a manual link is by name, for every source, and wins over the IP" do
    DnsLink.create!(name: "WWW.example.test", server: servers(:backup))
    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10") ])
    Dns::Store.replace("technitium", [ row("www.example.test", "A", "10.8.0.5") ])
    assert_equal [ servers(:backup) ] * 2, DnsRecord.where(name: "www.example.test").map(&:server)
    assert_equal %w[manual manual], DnsRecord.where(name: "www.example.test").pluck(:matched_by)

    DnsLink.find_by!(name: "www.example.test").update!(server: nil)
    Dns::Matcher.call
    assert_equal [ nil, nil ], DnsRecord.where(name: "www.example.test").pluck(:server_id), "attached to no server by hand"
  end

  test "a name differs between sources when their records do, not when they are the same" do
    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10"), row("same.example.test", "A", "203.0.113.20"), row("only-ovh.example.test", "A", "203.0.113.30") ])
    Dns::Store.replace("technitium", [ row("www.example.test", "A", "10.8.0.100"), row("same.example.test", "A", "203.0.113.20") ])
    assert_equal [ "www.example.test" ], DnsRecord.conflicting_names
    assert_equal 2, DnsRecord.conflicting.count
  end

  test "every name that leads to an IP, through CNAMEs and whatever the source" do
    Dns::Store.replace("ovh", [ row("www.example.test", "A", "203.0.113.10"), row("other.example.test", "A", "203.0.113.100"), row("v6.example.test", "AAAA", "2001:db8::1") ])
    Dns::Store.replace("technitium", [ row("intranet.lan.test", "CNAME", "www.example.test", zone: "lan.test"), row("deep.lan.test", "CNAME", "intranet.lan.test", zone: "lan.test") ])
    assert_equal %w[deep.lan.test intranet.lan.test www.example.test], DnsRecord.names_pointing_to(" 203.0.113.10 ")
    assert_equal %w[v6.example.test], DnsRecord.names_pointing_to("2001:DB8:0:0:0:0:0:1")
    assert_equal [], DnsRecord.names_pointing_to("198.51.100.1")
    assert_nil DnsRecord.names_pointing_to("www")
    assert_nil DnsRecord.names_pointing_to("203.0.113.0/24")
    assert_nil DnsRecord.names_pointing_to("")
  end

  test "a server is found by one of its DNS names (fleet search, ⌘K)" do
    Dns::Store.replace("technitium", [ row("intranet.lan.test", "A", "203.0.113.10", zone: "lan.test") ])
    server = Server.includes(:dns_records).find(servers(:web).id)
    assert_equal [ "intranet.lan.test" ], server.dns_names
    assert server.matches_search?("intranet")
    assert_not servers(:db).matches_search?("intranet")
  end
end
