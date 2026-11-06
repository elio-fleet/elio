require "test_helper"

class ServerPromptTest < ActiveSupport::TestCase
  include PortHelpers

  setup do
    @server = servers(:web)
    snapshot = ->(category, data) { @server.inventory_snapshots.create!(category: category, status: "ok", data: data, collected_at: Time.current, checked_at: Time.current) }
    snapshot.("os", { "name" => "Debian GNU/Linux 13 (trixie)", "kernel" => "6.12.48+deb13-amd64", "hostname" => "web-1", "virtualization" => "kvm" })
    snapshot.("network", { "addresses" => [
      { "address" => "203.0.113.10", "family" => "ipv4", "prefix" => 24, "scope" => "public", "interface" => "eth0", "kind" => "ethernet" },
      { "address" => "10.8.0.100", "family" => "ipv4", "prefix" => 24, "scope" => "private", "interface" => "wg0", "kind" => "wireguard" },
      { "address" => "2001:db8::abcd", "family" => "ipv6", "prefix" => 64, "scope" => "public", "interface" => "eth0", "kind" => "ethernet", "temporary" => true }
    ] })
    snapshot.("services", { "docker" => "ok",
      "units" => [ { "name" => "nginx.service", "active" => "active", "sub" => "running", "description" => "A high performance web server" },
                   { "name" => "old.service", "active" => "inactive", "sub" => "dead" } ],
      "containers" => [ { "name" => "shop-web-1", "image" => "nginx:1.27", "state" => "running", "ports" => "0.0.0.0:8080->80/tcp", "project" => "shop" } ] })
    record_ports(@server)
    @server.server_groups.first&.update!(expected_ports: "22, 443")
    UptimeKumaMonitor.create!(monitor_id: "1", name: "Web HTTPS", monitor_type: "http", url: "https://www.example.com/", status: 1, server: @server)
    OvhResource.create!(kind: "ip", external_id: "203.0.113.10/32", name: "203.0.113.10/32", server: @server, data: { "firewall" => {
      "203.0.113.10" => { "enabled" => true, "rules" => [ { "sequence" => 1, "action" => "deny", "protocol" => "tcp", "destinationPort" => "eq 3306" },
                                                          { "sequence" => 0, "action" => "permit", "protocol" => "tcp", "destinationPort" => "eq 22", "source" => "198.51.100.7/32" } ] } } })
  end

  test "the monitors prompt: context, services, containers, ports, existing monitors, the task" do
    text = ServerPrompt.new(@server).monitors

    assert text.start_with?("Je surveille mes serveurs Linux avec Uptime Kuma.")
    assert_includes text, "- Nom dans Elio : Web"
    assert_includes text, "- Nom d'hôte : web-1"
    assert_includes text, "- Système : Debian GNU/Linux 13 (trixie), 6.12.48+deb13-amd64"
    assert_includes text, "- Adresse SSH utilisée par Elio : #{@server.host}:22"
    assert_includes text, "- 203.0.113.10/24 (ipv4, publique, eth0)"
    assert_includes text, "- 10.8.0.100/24 (ipv4, privée / VPN, wg0, wireguard)"
    assert_not_includes text, "2001:db8::abcd", "temporary IPv6 addresses are left out"
    assert_includes text, "- nginx.service — A high performance web server"
    assert_not_includes text, "old.service"
    assert_includes text, "- shop-web-1, image nginx:1.27, running, ports 0.0.0.0:8080->80/tcp, projet Compose shop"
    assert_match %r{^- 22/tcp sur .+\(publique\)}, text
    assert_includes text, "- Web HTTPS (http, https://www.example.com/) — up"
    assert_includes text, "## Ce que je demande\nPropose la liste des sondes à créer"
  end

  test "the firewall prompt without OVH: the machine's firewall only, as ufw commands" do
    text = ServerPrompt.new(@server).firewall

    assert text.start_with?("Voici ce qu'Elio (un outil d'inventaire) sait de mon serveur Linux.")
    assert_includes text, "## Firewall de la machine"
    assert_not_includes text, "OVHcloud"
    assert_includes text, "commandes ufw"
  end

  test "the firewall prompt with OVH: public ports, the machine's firewall, the network firewall rules in order" do
    Integration.create!(kind: "ovh").update_column(:enabled, true)
    text = ServerPrompt.new(@server).firewall

    assert text.start_with?("Mon serveur Linux est hébergé chez OVHcloud.")
    assert_includes text, "## Ports publics"
    assert_includes text, "## Firewall de la machine"
    assert_includes text, "- 203.0.113.10 : activé, 2 règles"
    assert_operator text.index("n°0 permit tcp port eq 22 source 198.51.100.7/32"), :<, text.index("n°1 deny tcp port eq 3306 source any")
    assert_includes text, "Garde l'accès SSH d'Elio ouvert sur le port 22"
    assert_not_includes text, "## Sondes"
  end

  test "never anything secret" do
    Integration.create!(kind: "ovh", enabled: true, settings: { "application_key" => "AK-public-looking" }, secrets: { "application_secret" => "SECRET-AS", "consumer_key" => "SECRET-CK" })
    @server.notes.create!(body: "password: hunter2", user: users(:one))
    [ ServerPrompt.new(@server).monitors, ServerPrompt.new(@server).firewall ].each do |text|
      [ "SECRET-AS", "SECRET-CK", "AK-public-looking", "hunter2", ssh_keys(:main).public_key.split[1], "PRIVATE KEY" ].each do |secret|
        assert_not_includes text, secret
      end
    end
  end

  test "the instructions of the administrator come last, only in their prompt" do
    AppSetting.current.update!(prompt_instructions: { "firewall" => "Pour le port SSH, mets les règles toujours en dernier." })

    text = ServerPrompt.new(@server).firewall
    assert text.end_with?("## Consignes supplémentaires\nPour le port SSH, mets les règles toujours en dernier.")
    assert_operator text.index("## Ce que je demande"), :<, text.index("## Consignes supplémentaires")
    assert_not_includes ServerPrompt.new(@server).monitors, "Consignes supplémentaires"
  end

  test "in the reader's language, and without inventory" do
    I18n.with_locale(:en) do
      text = ServerPrompt.new(servers(:db)).monitors
      assert text.start_with?("I monitor my Linux servers with Uptime Kuma.")
      assert_includes text, "## Listening ports\n(no inventory of the ports yet)"
      assert_includes text, "## Active systemd services\n(none)"
    end
  end
end
