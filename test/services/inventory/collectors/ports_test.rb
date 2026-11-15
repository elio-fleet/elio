require "test_helper"

class Inventory::Collectors::PortsTest < ActiveSupport::TestCase
  Collector = Inventory::Collectors::Ports

  def sections(name) = Inventory::Collector.sections(file_fixture("inventory/ports/#{name}.txt").read)

  def parse(name) = Collector.parse(sections(name))

  test "parses the listening ports with their process, unit and scope" do
    listening = parse(:debian12)["listening"]

    assert_equal [ [ 22, "tcp", "0.0.0.0" ], [ 22, "tcp", "::" ], [ 53, "udp", "127.0.0.53" ], [ 3306, "tcp", "127.0.0.1" ], [ 5050, "tcp", "127.0.0.1" ],
                   [ 5432, "tcp", "10.0.1.20" ], [ 6432, "tcp", "0.0.0.0" ], [ 9100, "tcp", "*" ], [ 41_641, "udp", "100.64.0.12" ] ],
                 listening.map { |entry| entry.values_at("port", "proto", "address") }
    assert_equal({ "proto" => "tcp", "address" => "0.0.0.0", "port" => 22, "scope" => "public", "process" => "sshd", "pid" => 812, "unit" => "ssh.service" }, listening.first)
    assert_equal %w[local private], listening.select { |entry| [ 53, 5432 ].include?(entry["port"]) }.map { |entry| entry["scope"] }
    assert_equal "postgresql@15-main.service", listening.find { |entry| entry["port"] == 5432 }["unit"]
    assert_equal "private", listening.last["scope"]
  end

  test "classifies the listening addresses" do
    { "0.0.0.0" => "public", "::" => "public", "*" => "public", "51.38.12.4" => "public", "2001:db8::1" => "public",
      "127.0.0.1" => "local", "::1" => "local", "10.2.3.4" => "private", "192.168.1.1" => "private", "172.20.0.1" => "private",
      "fd12::1" => "private", "fe80::1" => "private", "not-an-ip" => "public" }.each do |address, scope|
      assert_equal scope, Collector.scope(address), address
    end
    assert_equal [ "127.0.0.1", "6379" ], Collector.split_address("[::ffff:127.0.0.1]:6379")
  end

  test "reads an active ufw: default policy, rules, application profiles, sources and the family of each rule" do
    assert_equal({ "tool" => "ufw", "active" => true, "default_incoming" => "deny",
                   "allowed" => [ { "rule" => "22/tcp", "family" => "ipv4" }, { "rule" => "80/tcp", "family" => "ipv4" }, { "rule" => "443/tcp", "family" => "ipv4" },
                                  { "rule" => "5432", "from" => "10.0.0.0/16", "family" => "ipv4" }, { "rule" => "22/tcp", "family" => "ipv6" } ] },
                 parse(:debian12)["firewall"])
  end

  test "reads nftables and iptables when ufw is not active" do
    assert_equal({ "tool" => "nftables", "active" => true, "default_incoming" => "deny",
                   "allowed" => [ { "rule" => "22/tcp" }, { "rule" => "80/tcp" }, { "rule" => "443/tcp" }, { "rule" => "51820/udp" } ] }, parse(:nft)["firewall"])
    assert_equal({ "tool" => "iptables", "active" => true, "default_incoming" => "deny",
                   "allowed" => [ { "rule" => "22/tcp", "family" => "ipv4" }, { "rule" => "80,443/tcp", "from" => "10.0.0.0/8", "family" => "ipv4" } ] }, parse(:iptables)["firewall"])
  end

  test "reads firewalld: services as their ports, port ranges, zones limited to sources, rich rules with their family" do
    assert_equal({ "tool" => "firewalld", "active" => true, "default_incoming" => "deny",
                   "allowed" => [ { "rule" => "546/udp" }, { "rule" => "80/tcp" }, { "rule" => "22/tcp" }, { "rule" => "8080/tcp" }, { "rule" => "9000:9100/udp" },
                                  { "rule" => "5432/tcp", "from" => "10.0.0.0/8", "family" => "ipv4" }, { "rule" => "22/tcp", "from" => "2001:db8::/32", "family" => "ipv6" },
                                  { "rule" => "22/tcp", "from" => "192.168.10.0/24" } ] },
                 parse(:firewalld)["firewall"])

    accept = "trusted (active)\n  target: ACCEPT\n  sources: \n  services: \n  ports: \n"
    assert_equal "allow", Collector.parse_firewalld(accept, "")["default_incoming"]
    assert_equal({ "tool" => "unknown", "active" => nil }, Collector.parse_firewall("ufw" => "absent", "firewalld" => "Authorization failed.", "nft" => "absent", "iptables" => "absent"))
    assert_equal "none", Collector.parse_firewall("ufw" => "absent", "firewalld" => "not running", "nft" => "absent", "iptables" => "absent")["tool"]
  end

  test "flags an IPv6 left open while IPv4 is filtered" do
    assert parse(:ufw_docker)["firewall"]["ipv6_open"], "ufw with IPV6=no: ip6tables accepts everything"
    assert_nil Collector.parse_iptables("-P INPUT DROP\n", "-P INPUT DROP\n-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT\n")["ipv6_open"]
    assert_equal [ { "rule" => "22/tcp", "family" => "ipv6" } ], Collector.parse_iptables("-P INPUT DROP\n", "-P INPUT DROP\n-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT\n")["allowed"]

    ip_only = "table ip filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy drop;\n\t\ttcp dport 22 accept\n\t}\n}\n"
    assert_equal({ "tool" => "nftables", "active" => true, "default_incoming" => "deny", "allowed" => [ { "rule" => "22/tcp", "family" => "ipv4" } ], "ipv6_open" => true },
                 Collector.parse_nft(ip_only))
    both = ip_only + "table ip6 filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy drop;\n\t}\n}\n"
    assert_nil Collector.parse_nft(both)["ipv6_open"]
    assert_nil parse(:nft)["firewall"]["ipv6_open"], "an inet table filters both families"
  end

  test "reads the DOCKER-USER chain of Docker" do
    assert_equal [ "-j ufw-user-forward", "-s 10.0.0.0/8 -j RETURN", "-p tcp -m tcp --dport 8080 -j DROP" ], parse(:ufw_docker)["firewall"]["docker_user"]
    assert_equal [], Collector.parse_firewall("ufw" => "absent", "nft" => "absent", "iptables" => "absent", "docker_user" => "-N DOCKER-USER\n-A DOCKER-USER -j RETURN\n")["docker_user"]
    assert_not parse(:firewalld)["firewall"].key?("docker_user"), "no chain: no Docker"
    assert_not parse(:debian12)["firewall"].key?("docker_user"), "older output without the section"
  end

  test "without root, processes and firewall are unknown" do
    data = parse(:no_root)

    assert_equal [ [ 22, nil ], [ 80, nil ] ], data["listening"].select { |entry| entry["address"] == "0.0.0.0" }.map { |entry| entry.values_at("port", "process") }
    assert_equal({ "tool" => "unknown", "active" => nil }, data["firewall"])
  end

  test "no firewall at all" do
    assert_equal({ "tool" => "none", "active" => false }, Collector.parse_firewall("ufw" => "absent\n", "nft" => "absent\n", "iptables" => "absent\n"))
  end

  test "collects through sudo, partial without root" do
    output = file_fixture("inventory/ports/debian12.txt").read
    [ [ true, "ok" ], [ false, "partial" ] ].each do |sudo, status|
      known_hosts = Rails.root.join("tmp", "test", "ports-#{SecureRandom.hex(4)}", "known_hosts")
      fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", sudo ? 0 : 1) },
                         handler: ->(command) { FakeSsh::Response.new(output, "", 0) if command.include?("sh -c") })
      outcome = Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Collector.new(ssh).collect }
      assert_equal status, outcome.status
      assert_equal sudo, fake.commands.last.start_with?("sudo -n sh -c")
      FileUtils.rm_rf(known_hosts.dirname)
    end
  end

  test "logs the public ports that open or close" do
    previous = { "listening" => [ { "port" => 22, "proto" => "tcp", "scope" => "public" }, { "port" => 8080, "proto" => "tcp", "scope" => "public" } ] }
    data = { "listening" => [ { "port" => 22, "proto" => "tcp", "scope" => "public" }, { "port" => 3306, "proto" => "tcp", "scope" => "public", "process" => "mariadbd" },
                              { "port" => 6379, "proto" => "tcp", "scope" => "local" } ] }

    assert_equal [ { kind: :port_opened, data: { port: "3306/tcp", process: "mariadbd" } }, { kind: :port_closed, data: { port: "8080/tcp" } } ],
                 Collector.changes(previous, data)
  end

  test "an iptables or nftables that accepts everything without any rule is no firewall" do
    accept_all = "-P INPUT ACCEPT\n-P FORWARD ACCEPT\n-P OUTPUT ACCEPT\n"
    assert_equal({ "tool" => "none", "active" => false }, Collector.parse_firewall("ufw" => "absent", "nft" => "absent", "iptables" => accept_all))

    open_nft = "table inet filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy accept;\n\t}\n}\n"
    assert_equal({ "tool" => "none", "active" => false }, Collector.parse_firewall("ufw" => "absent", "nft" => open_nft, "iptables" => "absent"))
  end
end
