require "test_helper"

class Inventory::PortAnalysisTest < ActiveSupport::TestCase
  setup do
    @server = servers(:db) # in group Production
    @server.update_columns(port: 22)
  end

  def collect_ports(name = :debian12, firewall: nil)
    data = Inventory::Collectors::Ports.parse(Inventory::Collector.sections(file_fixture("inventory/ports/#{name}.txt").read))
    data["firewall"] = firewall if firewall
    @server.inventory_snapshots.create!(category: "ports", status: "ok", data: data, collected_at: Time.current, checked_at: Time.current)
  end

  def collect_containers(containers)
    @server.inventory_snapshots.create!(category: "services", status: "ok", data: { "units" => [], "containers" => containers, "docker" => "ok" },
                                        collected_at: Time.current, checked_at: Time.current)
  end

  def analysis = Inventory::PortAnalysis.new(@server.reload)

  test "merges the addresses of a port, sorts public ports first and links the Docker containers" do
    collect_ports
    collect_containers([ { "name" => "pgbouncer", "state" => "running", "ports" => "0.0.0.0:6432->6432/tcp, :::6432->6432/tcp" },
                         { "name" => "pgadmin", "state" => "running", "ports" => "127.0.0.1:5050->80/tcp" },
                         { "name" => "grafana", "state" => "running", "ports" => "0.0.0.0:3000->3000/tcp" },
                         { "name" => "old", "state" => "exited", "ports" => "0.0.0.0:8080->80/tcp" } ])

    ports = analysis.ports

    assert_equal %w[22/tcp 3000/tcp 6432/tcp 9100/tcp 5432/tcp 41641/udp 53/udp 3306/tcp 5050/tcp], ports.map(&:key)
    ssh = ports.first
    assert_equal [ [ "0.0.0.0", "::" ], "public", "sshd", "ssh.service", nil, "allowed" ], [ ssh.addresses, ssh.scope, ssh.process, ssh.unit, ssh.container, ssh.firewall ]
    assert_equal [ "pgbouncer", "docker" ], ports.find { |port| port.port == 6432 }.then { |port| [ port.container, port.firewall ] }
    assert_equal [ "dockerd", "grafana", "docker" ], ports.find { |port| port.port == 3000 }.then { |port| [ port.process, port.container, port.firewall ] }
    assert_equal "blocked", ports.find { |port| port.port == 9100 }.firewall
    assert_nil ports.find { |port| port.port == 5432 }.firewall
    assert_equal "pgadmin", ports.find { |port| port.port == 5050 }.container
    assert_equal "ufw actif (entrant : bloqué par défaut)", analysis.firewall_label
  end

  test "ports are open without a filtering firewall, unknown without root" do
    collect_ports(firewall: { "tool" => "none", "active" => false })
    assert_equal %w[open], analysis.public_ports.map(&:firewall).uniq
    assert_equal "aucun firewall actif", analysis.firewall_label

    @server.inventory_snapshots.destroy_all
    collect_ports(:no_root)
    assert_equal %w[unknown], analysis.public_ports.map(&:firewall).uniq
    assert_equal "firewall inconnu (accès root requis)", analysis.firewall_label
  end

  test "rules with ranges, lists and no protocol" do
    collect_ports(firewall: { "tool" => "iptables", "active" => true, "default_incoming" => "deny",
                              "allowed" => [ { "rule" => "9000:9200/tcp" }, { "rule" => "22,80/tcp" }, { "rule" => "6432" } ] })

    assert_equal %w[allowed allowed allowed], analysis.public_ports.map(&:firewall)
  end

  test "flags the public ports the groups do not expect, and makes them a health reason" do
    server_groups(:production).update!(expected_ports: "22, 80, 443/tcp")
    collect_ports
    @server.update_columns(ssh_ok: true)

    assert_equal %w[6432/tcp 9100/tcp], analysis.unexpected_ports.map(&:key)
    @server.refresh_health!
    assert_equal [ "2 ports inattendus (6432/tcp, 9100/tcp)" ], @server.health_reason_texts
  end

  test "no expected ports, no check" do
    collect_ports
    assert_empty analysis.unexpected_ports
  end

  test "suggests ufw rules: SSH first, Docker and unexpected ports as comments, safe comments" do
    server_groups(:production).update!(expected_ports: "22, 6432, 9100")
    collect_ports
    collect_containers([ { "name" => "pgbouncer", "state" => "running", "ports" => "0.0.0.0:6432->6432/tcp" } ])
    @server.inventory_snapshots.of_category(:ports).sole.tap do |snapshot|
      snapshot.data["listening"] << { "port" => 8443, "proto" => "tcp", "address" => "0.0.0.0", "scope" => "public", "process" => "evil'; rm -rf /" }
      snapshot.save!
    end

    rules = analysis.suggested_ufw_rules.lines.map(&:chomp)

    assert_equal [ "# Règles ufw suggérées pour Database (à relire avant de les appliquer)", "sudo ufw default deny incoming",
                   "sudo ufw default allow outgoing", "sudo ufw allow 22/tcp comment 'ssh (Elio)'" ], rules.first(4)
    assert_includes rules, "# 6432/tcp publié par Docker (pgbouncer) : ufw ne le filtre pas. Publiez-le sur 127.0.0.1 ou filtrez-le dans la chaîne DOCKER-USER."
    assert_includes rules, "sudo ufw allow 9100/tcp comment 'node-exporter'"
    assert_includes rules, "# 8443/tcp (evil rm -rf ) : port inattendu, à fermer ou à ajouter aux ports attendus du groupe"
    assert_includes rules, "# 5432/tcp (postgresql@15-main) écoute sur le réseau privé (10.0.1.20) : à autoriser depuis ce réseau si besoin"
    assert_equal "sudo ufw enable", rules.last
    assert_not rules.any? { |rule| rule.include?("3306") }
  end

  test "with SSH sources, the SSH rules allow only them, with a reminder for Elio's own address" do
    SshSource.create!(name: "Elio", cidr: "203.0.113.5", position: 0)
    SshSource.create!(name: "Bureau d'Anna", cidr: "2001:db8:1::/48", position: 1)
    collect_ports

    rules = analysis.suggested_ufw_rules.lines.map(&:chomp)

    assert_equal [ "# SSH seulement depuis : Elio, Bureau d'Anna (Paramètres → Général → Règles de firewall proposées)",
                   "# L'adresse d'Elio doit en faire partie, sinon Elio perd son accès SSH.",
                   "sudo ufw allow from 203.0.113.5 to any port 22 proto tcp comment 'ssh (Elio)'",
                   "sudo ufw allow from 2001:db8:1::/48 to any port 22 proto tcp comment 'ssh (Bureau dAnna)'" ], rules[3, 4]
    assert_not rules.any? { |rule| rule.start_with?("sudo ufw allow 22/tcp") }
  end

  test "nothing collected" do
    assert_not analysis.collected?
    assert_empty analysis.ports
  end
end
