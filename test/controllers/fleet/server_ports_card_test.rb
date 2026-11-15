require "test_helper"

class ServerPortsCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  test "shows the ports, their exposure and firewall state, the Docker warning and the ufw rules" do
    servers(:db).update_columns(port: 22)
    server_groups(:production).update!(expected_ports: "22, 6432")
    record_ports(servers(:db))
    record_containers(servers(:db), [ { "name" => "pgbouncer", "state" => "running", "ports" => "0.0.0.0:6432->6432/tcp" } ])
    sign_in users(:viewer)

    get server_path(servers(:db), tab: "firewall")

    assert_select "#server-ports" do
      assert_select ".ports-summary", text: /3 publics sur 8 en écoute/
      assert_select ".firewall-state", text: "Firewall : ufw actif (entrant : bloqué par défaut)"
      assert_select ".ports-summary", text: /Ports attendus : 22, 6432/
      assert_select ".docker-bypass", text: /DOCKER-USER/
      assert_select "tr.port", 8
      assert_select "tr.port:first-child", text: /22\/tcp.*0\.0\.0\.0 toutes les interfaces IPv4.*:: toutes les interfaces.*public.*sshd.*ssh.*autorisé/m
      assert_select "tr.port[data-scope=local] .listen-address", text: /cette machine seulement/
      assert_select "tr.port", text: /6432\/tcp.*conteneur pgbouncer.*publié par Docker/m
      assert_select "tr.port", text: /9100\/tcp\s+inattendu.*bloqué/m
      assert_select "tr.port[data-scope=local]", 3
      assert_select ".ufw-rules", 0
    end
  end

  test "the Firewall tab: the server's firewall and its rules, the public ports, the ufw rules and the prompt" do
    servers(:db).update_columns(port: 22)
    record_ports(servers(:db))
    record_containers(servers(:db), [ { "name" => "pgbouncer", "state" => "running", "ports" => "0.0.0.0:6432->6432/tcp" } ])
    sign_in users(:viewer)

    get server_path(servers(:db), tab: "firewall")

    assert_select "nav.server-tabs a[data-tab=firewall][aria-current=page]", text: "Firewall"
    assert_select "#server-local-firewall .firewall-state", text: "ufw actif (entrant : bloqué par défaut)"
    assert_select "#server-local-firewall .local-firewall-rule", text: /22\/tcp.*depuis partout/m
    assert_select "#server-firewall-ports tr.firewall-port[data-port='22/tcp']", text: /autorisé/
    assert_select "#server-firewall-ports tr.firewall-port[data-port='6432/tcp']", text: /publié par Docker/
    assert_select "#server-firewall-ports .docker-bypass", text: /DOCKER-USER/
    assert_select "#server-firewall-ports th", text: /OVH/, count: 0
    assert_select "#server-ovh-firewall", 0
    assert_select "#server-firewall-suggested textarea[data-clipboard-target=source]", text: /sudo ufw allow 22\/tcp comment 'ssh \(Elio\)'/
    assert_select "#server-firewall .server-prompt[data-kind=firewall] dialog textarea.server-prompt-text", text: /Propose les règles de son firewall.*commandes ufw/m
  end

  test "the Firewall tab: IPv4 and IPv6 rules apart, an IPv6 left open, the DOCKER-USER chain and the prompt" do
    server = servers(:db)
    server.update_columns(port: 22, extra_addresses: [ "2001:db8::10" ])
    record_ports(server, :ufw_docker)
    record_containers(server, [ { "name" => "web", "state" => "running", "ports" => "0.0.0.0:8080->80/tcp" } ])
    sign_in users(:viewer)

    get server_path(server, tab: "firewall")

    assert_select "#server-local-firewall h3.local-firewall-family", text: "IPv4"
    assert_select "#server-local-firewall h3.local-firewall-family", text: "IPv6"
    assert_select "#server-local-firewall ul.local-firewall-rules[data-family=ipv6] .local-firewall-rule", text: %r{443/tcp.*depuis 2001:db8::/32}m
    assert_select "#server-local-firewall ul.local-firewall-rules[data-family=ipv4] .local-firewall-rule", text: %r{22/tcp.*depuis partout}m
    assert_select "#server-local-firewall .ipv6-open", text: /ufw ne filtre que l'IPv4.*22\/tcp.*2001:db8::10/m
    assert_select "#server-local-firewall .docker-user .docker-user-rule", 3
    assert_select "#server-local-firewall .docker-user-rule", text: "-p tcp -m tcp --dport 8080 -j DROP"
    assert_select "#server-firewall-ports tr.firewall-port[data-port='8080/tcp']", text: /Docker, règles DOCKER-USER/
    assert_select "#server-firewall-ports .docker-bypass", 0
    assert_select "textarea.server-prompt-text", text: %r{autorise 443/tcp depuis 2001:db8::/32 \(IPv6 seulement\).*IPv6 non filtré.*DOCKER-USER \(Docker\) : -j ufw-user-forward}m

    server.inventory_snapshots.where(category: "ports").destroy_all
    record_ports(server, :debian12, firewall: { "tool" => "ufw", "active" => true, "default_incoming" => "deny", "allowed" => [ { "rule" => "22/tcp" } ], "docker_user" => [] })
    get server_path(server, tab: "firewall")
    assert_select "#server-local-firewall .local-firewall-family", 0
    assert_select "#server-local-firewall .ipv6-open", 0
    assert_select "#server-local-firewall .docker-user", text: /Aucune règle : les ports publiés par Docker contournent/
    assert_select "#server-firewall-ports tr.firewall-port[data-port='8080/tcp']", text: /publié par Docker/
  end

  test "the Firewall tab without inventory, and without root" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "firewall")
    assert_select "#server-local-firewall", text: /Pas encore d'inventaire des ports/
    assert_select "#server-firewall-ports", 0

    record_ports(servers(:web), firewall: { "tool" => "unknown" })
    get server_path(servers(:web), tab: "firewall")
    assert_select "#server-local-firewall", text: /qu'en root/
  end

  test "before any inventory" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "firewall")
    assert_select "#server-ports .ports-empty", "Pas encore d'inventaire des ports."
  end
end
