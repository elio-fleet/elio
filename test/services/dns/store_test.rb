require "test_helper"

# The DNS of the fleet, fed by several sources (phase 14).
class Dns::StoreTest < ActiveSupport::TestCase
  setup do
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
end
