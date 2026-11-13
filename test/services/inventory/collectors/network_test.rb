require "test_helper"

class Inventory::Collectors::NetworkTest < ActiveSupport::TestCase
  def sections(name = "debian13-wireguard")
    Inventory::Collector.sections(file_fixture("inventory/network/#{name}.txt").read)
  end

  test "parses a real Debian 13 output: ethernet, WireGuard, container bridge left out" do
    data = Inventory::Collectors::Network.parse(sections)

    assert_equal %w[ens18 wg0], data["interfaces"].map { |interface| interface["name"] }
    ens18, wg0 = data["interfaces"]
    assert_equal [ "ethernet", "UP", "02:00:00:00:00:01", true ], ens18.values_at("kind", "state", "mac", "up")
    assert_equal "wireguard", wg0["kind"]
    assert_equal [ { "address" => "10.8.0.48", "family" => "ipv4", "prefix" => 24, "scope" => "private" } ], wg0["addresses"]

    addresses = data["addresses"].to_h { |address| [ address["address"], address.values_at("scope", "interface", "kind") ] }
    assert_equal [ "private", "ens18", "ethernet" ], addresses["10.0.0.48"]
    assert_equal [ "public", "ens18", "ethernet" ], addresses["2001:db8:868:4c00:be24:11ff:fed4:6200"]
    assert_equal [ "private", "ens18", "ethernet" ], addresses["fd00:1:2:3:be24:11ff:fed4:6200"]
    assert_not addresses.key?("127.0.0.1"), "loopback left out"
    assert_not addresses.key?("fe80::1"), "link-local left out"
    assert_not addresses.key?("172.17.0.1"), "Docker bridge left out"
  end

  test "inside a container (an LXC on Proxmox), eth0 is a veth: kept as the server's ethernet" do
    data = Inventory::Collectors::Network.parse(sections("container-veth"))

    eth0 = data["interfaces"].find { |interface| interface["name"] == "eth0" }
    assert_equal "ethernet", eth0["kind"]
    assert_equal [ "172.24.0.2" ], eth0["addresses"].map { |address| address["address"] }
    assert_equal [ "172.24.0.2" ], Inventory::Collectors::Network.server_attributes(data)[:ip_addresses]
  end

  test "the host side of veth pairs stays left out" do
    addr = [ { "ifname" => "veth7e76454", "link_type" => "ether", "addr_info" => [ { "family" => "inet", "local" => "10.9.9.9", "prefixlen" => 24, "scope" => "global" } ] },
             { "ifname" => "veth100i0", "link_type" => "ether", "addr_info" => [ { "family" => "inet", "local" => "10.9.9.8", "prefixlen" => 24, "scope" => "global" } ] } ]
    links = addr.map { |entry| entry.slice("ifname", "link_type").merge("linkinfo" => { "info_kind" => "veth" }) }

    assert_empty Inventory::Collectors::Network.parse({ "addr" => addr.to_json, "link" => links.to_json })["interfaces"]
  end

  test "server summary: every address, public first" do
    attributes = Inventory::Collectors::Network.server_attributes(Inventory::Collectors::Network.parse(sections))
    assert_equal "2001:db8:868:4c00:be24:11ff:fed4:6200", attributes[:ip_addresses].first
    assert_includes attributes[:ip_addresses], "10.8.0.48"
    assert_equal 4, attributes[:ip_addresses].size
  end

  test "link kinds" do
    links = [
      { "ifname" => "eth0", "link_type" => "ether" }, { "ifname" => "wlan0", "link_type" => "ether" },
      { "ifname" => "tun0", "link_type" => "none", "linkinfo" => { "info_kind" => "tun", "info_data" => { "type" => "tun" } } },
      { "ifname" => "tap0", "link_type" => "ether", "linkinfo" => { "info_kind" => "tun", "info_data" => { "type" => "tap" } } },
      { "ifname" => "eth0.10", "link_type" => "ether", "linkinfo" => { "info_kind" => "vlan" } },
      { "ifname" => "gre1", "link_type" => "gre", "linkinfo" => { "info_kind" => "gre" } },
      { "ifname" => "x", "link_type" => "ether", "linkinfo" => { "info_kind" => "macvlan" } }
    ]
    assert_equal({ "eth0" => "ethernet", "wlan0" => "wifi", "tun0" => "tun", "tap0" => "tap", "eth0.10" => "vlan", "gre1" => "tunnel", "x" => "other" },
                 Inventory::Collectors::Network.parse_links(links.to_json))
  end

  test "an old ip without JSON support, and an invalid output" do
    assert_equal({}, Inventory::Collectors::Network.parse_links("Option \"-j\" is unknown"))
    assert_equal "unsupported", run_collector("@@elio addr\nunsupported\n@@elio link\n").status
    assert_equal "ok", run_collector(file_fixture("inventory/network/debian13-wireguard.txt").read).status

    error = assert_raises(Inventory::Collector::Error) { run_collector("@@elio addr\n[{oops\n@@elio link\n") }
    assert_match "illisible", error.message
  end

  test "changes: public addresses added or removed, temporary IPv6 ignored" do
    previous = { "addresses" => [ { "address" => "203.0.113.4", "scope" => "public" }, { "address" => "10.8.0.4", "scope" => "private" },
                                  { "address" => "2001:db8::aaaa", "scope" => "public", "temporary" => true } ] }
    data = { "addresses" => [ { "address" => "203.0.113.5", "scope" => "public" }, { "address" => "2001:db8::bbbb", "scope" => "public", "temporary" => true } ] }

    assert_equal [ { kind: :ip_address_added, data: { address: "203.0.113.5" } }, { kind: :ip_address_removed, data: { address: "203.0.113.4" } } ],
                 Inventory::Collectors::Network.changes(previous, data)
  end

  test "is part of the system inventory automation" do
    assert_equal %w[os network], Automation::KINDS.fetch(:inventory_os).categories
    assert_equal "Réseau", Inventory::Collector.label_for("network")
  end

  private

  def run_collector(stdout)
    known_hosts = Rails.root.join("tmp", "test", "network-#{SecureRandom.hex(4)}", "known_hosts")
    fake = FakeSsh.new(handler: ->(command) { FakeSsh::Response.new(stdout, "", 0) if command.start_with?("sh -c") })
    Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Inventory::Collectors::Network.new(ssh).collect }
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end
end
