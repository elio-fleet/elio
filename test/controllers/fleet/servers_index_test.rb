require "test_helper"

class ServersIndexTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "requires authentication" do
    get servers_path
    assert_redirected_to new_user_session_path
  end

  test "lists servers sorted by name" do
    sign_in users(:one)
    get servers_path

    assert_select "#servers tbody tr", Server.count
    assert_select "#servers tbody tr:first-child td:nth-child(2) a", "Backup"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))}" do
      assert_select ".server-address", "deploy@192.168.1.10"
      assert_select ".server-os", text: "—"
    end
    assert_select "a[href=?]", new_server_path, text: "Ajouter un serveur"
  end

  test "filters the servers by group and shows their group badges" do
    sign_in users(:one)
    production = server_groups(:production)

    get servers_path
    assert_select "nav.server-group-filter" do
      assert_select "a[aria-current=page]", "Tous"
      assert_select "a[href=?]", servers_path(group: production.id), text: "Production"
      assert_select "a[href=?]", server_groups_path, text: "Gérer les groupes"
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} a.server-group-badge[href=?]", servers_path(group: production.id), text: "Production"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:backup))} a.server-group-badge", 0

    get servers_path(group: production.id)
    assert_select "#servers tbody tr", 2
    assert_select "#servers tbody tr td", text: "Backup", count: 0
    assert_select "nav.server-group-filter a[aria-current=page]", "Production"
  end

  test "an empty group offers to add servers to it, an unknown group shows everything" do
    sign_in users(:one)

    get servers_path(group: server_groups(:staging).id)
    assert_select "p", text: "Aucun serveur dans ce groupe."
    assert_select "a[href=?]", edit_server_group_path(server_groups(:staging)), text: "Ajouter des serveurs au groupe"

    get servers_path(group: 0)
    assert_select "#servers tbody tr", Server.count
  end

  test "without groups, invites to create some" do
    ServerGroup.delete_all
    sign_in users(:one)
    get servers_path

    assert_select "nav.server-group-filter a[href=?]", server_groups_path, text: "Organiser les serveurs en groupes"
    assert_select "nav.server-group-filter a[aria-current]", 0
  end

  test "shows an empty state when there are no servers" do
    Server.delete_all
    sign_in users(:one)
    get servers_path

    assert_select "#servers", 0
    assert_select "p", text: "Aucun serveur pour le moment."
  end

  test "shows the reachability status of each server" do
    sign_in users(:one)
    get servers_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .server-status", text: "En ligne"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))} .server-status", text: "Injoignable"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:backup))} .server-status[title=?]", "Jamais vérifié", text: "Inconnu"
  end

  test "shows refresh buttons for all servers and for each server" do
    sign_in users(:one)
    get servers_path

    assert_select "form[action=?][method=post][data-action*='server-ping#start']", server_pings_path
    assert_select "form[action=?][method=post][data-server-ping-badge-param=?]", server_ping_path(servers(:web)),
                  ActionView::RecordIdentifier.dom_id(servers(:web), :status) do
      assert_select "button[title=?] svg", "Actualiser le statut"
    end
  end

  test "renders badges as Stimulus targets with a checking template" do
    sign_in users(:one)
    get servers_path

    assert_select "section[data-controller=server-ping]" do
      assert_select "template[data-server-ping-target=checking]"
      assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web), :status)}[data-server-ping-target=badge]"
    end
    assert_select "#flash"
  end

  test "shows an edit link for each server" do
    sign_in users(:one)
    get servers_path

    Server.find_each do |server|
      assert_select "a[href=?][title=Modifier][aria-label=?] svg", edit_server_path(server), "Modifier #{server.name}"
      assert_select "td a[href=?]", server_path(server), text: server.name
    end
  end

  test "notes a refused Elio key" do
    servers(:web).record_ssh_status!(true)
    servers(:db).record_ssh_status!(false)
    sign_in users(:one)

    get servers_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .ssh-status", 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))} .server-notes a.ssh-status[href=?]", server_path(servers(:db)), text: /Clé refusée/
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:backup))} .ssh-status", 0
  end

  test "notes the unknown keys of scanned servers" do
    unnamed = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse([ unnamed, bob, ssh_keys(:main).public_key, public_keys(:ci).content ].join("\n")))
    AccountSnapshot.record!(servers(:db), AuthorizedKeysAccount.login(servers(:db)), AuthorizedKey.parse(public_keys(:alice).content))
    sign_in users(:one)

    get servers_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .server-notes a.orphan-keys[title=?]", "sans nom, bob@desktop", text: "2 clés inconnues"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))} .orphan-keys", 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:backup))} .orphan-keys", 0
  end

  test "offers to scan the keys of every server" do
    sign_in users(:one)
    get servers_path
    assert_select "form[action=?] button", server_scans_path, text: /Scanner les clés/
  end

  test "shows each server's system and warns about its end of support" do
    servers(:web).update_columns(os_name: "Debian GNU/Linux 12 (bookworm)", os_id: "debian", os_version: "12")
    servers(:db).update_columns(os_name: "Debian GNU/Linux 10 (buster)", os_id: "debian", os_version: "10", port: 2222)
    sign_in users(:one)

    get servers_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .server-os span[title^='Debian GNU/Linux 12 (bookworm)']", text: "Debian 12"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))}" do
      assert_select ".server-os .badge", text: "plus supporté"
      assert_select ".server-address", "admin@db.example.com:2222"
    end
  end

  test "filters the servers by system, within a group too" do
    servers(:web).update_columns(os_name: "Debian GNU/Linux 12 (bookworm)")
    servers(:db).update_columns(os_name: "Ubuntu 24.04.1 LTS")
    sign_in users(:one)

    get servers_path(os: "Ubuntu 24.04.1 LTS")
    assert_select "#servers tbody tr", 1
    assert_select "#servers tbody tr td a", text: "Database"
    assert_select "form.fleet-filters[data-controller=auto-submit] .os-filter select[name=os] option[selected]", "Ubuntu 24.04.1 LTS"

    get servers_path(os: "Ubuntu 24.04.1 LTS", group: server_groups(:production).id)
    assert_select "#servers tbody tr", 1
    assert_select "form.fleet-filters input[type=hidden][name=group][value=?]", server_groups(:production).id.to_s

    get servers_path(os: "Windows")
    assert_select "#servers tbody tr", Server.count
  end

  def inventory_health(server, status:, reasons: [], data: {})
    server.inventory_snapshots.create!(category: "health", status: "ok", data: data, collected_at: Time.current, checked_at: Time.current)
    server.update_columns(health_status: status, health_reasons: reasons.map { |text| { "tone" => status, "text" => text } }, inventoried_at: 1.hour.ago)
  end

  test "sums up the fleet: online, to watch, critical and security updates" do
    servers(:web).update_columns(reachable: true)
    servers(:db).update_columns(reachable: false)
    servers(:backup).update_columns(reachable: true)
    inventory_health(servers(:web), status: "warn", reasons: [ "Redémarrage requis" ], data: { "updates" => { "total" => 5, "security" => 2 } })
    inventory_health(servers(:backup), status: "crit", reasons: [ "Disque / à 95 %" ], data: { "updates" => { "total" => 9, "security" => 4 } })
    sign_in users(:viewer)

    get servers_path

    assert_select "#stat-online .stat-value", "2/3"
    assert_select "#stat-to-watch .stat-value.text-warn-ink", "1"
    assert_select "#stat-critical .stat-value.text-crit-ink", "2"
    assert_select "#stat-critical", text: /dont 1 injoignable/
    assert_select "#stat-security .stat-value", "6"
    assert_select "#stat-security", text: /sur 2 serveurs/
    assert_select "p", text: /3 serveurs\s+· inventaire/
  end

  test "shows each server's health, gauges, updates and main reason" do
    servers(:web).update_columns(reachable: true)
    inventory_health(servers(:web), status: "crit", reasons: [ "Disque / à 95 %", "Redémarrage requis" ],
                     data: { "memory" => { "used_percent" => 61 }, "disk_max_percent" => 95, "updates" => { "total" => 3, "security" => 1 } })
    servers(:web).health_samples.create!(collected_at: 2.hours.ago, load_percent: 20)
    servers(:web).health_samples.create!(collected_at: 1.hour.ago, load_percent: 40)
    sign_in users(:viewer)

    get servers_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))}" do
      assert_select ".server-status[data-state=crit]", text: "Critique"
      assert_select ".server-status[title=?]", "Disque / à 95 % · Redémarrage requis"
      assert_select ".server-load svg.sparkline"
      assert_select ".server-memory .meter[data-tone=neutral]", text: "61\u00A0%"
      assert_select ".server-disk .meter[data-tone=crit]", text: "95\u00A0%"
      assert_select ".server-updates", text: /3\s+1 sécu/
      assert_select ".server-notes .text-crit-ink", "Disque / à 95 %"
      assert_select ".server-notes span[title=?]", "Redémarrage requis", text: "+1"
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))} .server-load", text: "—"
  end

  test "filters the servers by health state" do
    servers(:web).update_columns(reachable: true)
    servers(:db).update_columns(reachable: false)
    inventory_health(servers(:web), status: "warn", reasons: [ "Redémarrage requis" ])
    sign_in users(:viewer)

    get servers_path(state: "warn")
    assert_select "#servers tbody tr", 1
    assert_select "#servers tbody tr td a", text: "Web"
    assert_select ".state-filter select[name=state] option[selected][value=warn]"

    get servers_path(state: "off")
    assert_select "#servers tbody tr td a", text: "Database"

    get servers_path(state: "crit")
    assert_select "#servers", 0
    assert_select "a[href=?]", servers_path, text: "Retirer les filtres"
  end

  test "the status buttons ask for health badges" do
    sign_in users(:one)
    get servers_path

    assert_select "form[action=?] input[name=badge][value=health]", server_pings_path
    assert_select "form[action=?][data-server-ping-badge-param=?] input[name=badge][value=health]",
                  server_ping_path(servers(:web)), ActionView::RecordIdentifier.dom_id(servers(:web), :status)
    assert_select "form[action=?] button", server_inventories_path, text: /Inventorier tout le parc/
  end

  test "the fleet actions are grouped in a menu, adding a server stays a button" do
    sign_in users(:one)
    get servers_path

    assert_select "details#fleet-actions[data-controller=dropdown]" do
      assert_select "summary[aria-haspopup=menu]", text: /Actions/
      assert_select "[role=menu] [role=menuitem]", 4
      assert_select "form[action=?] button[role=menuitem]", server_inventories_path, text: /Inventorier tout le parc/
      assert_select "form[action=?] button[role=menuitem]", server_scans_path, text: /Scanner les clés de tout le parc/
      assert_select "a[role=menuitem][href=?]", new_server_import_path, text: /Importer des serveurs/
    end
    assert_select "#fleet-actions a[href=?]", new_server_path, 0
    assert_select "a.btn-primary[href=?]", new_server_path
  end

  test "a viewer's menu only refreshes the statuses" do
    sign_in users(:viewer)
    get servers_path

    assert_select "#fleet-actions [role=menuitem]", 1
    assert_select "#fleet-actions [role=menuitem]", text: /Actualiser les statuts/
  end

  test "the search reloads only the results frame" do
    sign_in users(:one)
    get servers_path(q: "web")

    assert_select "form.fleet-filters[data-turbo-frame=fleet-results][data-controller=auto-submit]:not([data-turbo-action])"
    assert_select "turbo-frame#fleet-results form.fleet-filters", 0
    assert_select "turbo-frame#fleet-results[target=_top]" do
      assert_select "#servers tbody tr", 1
      assert_select "nav.server-group-filter"
      assert_select ".view-toggle"
    end
  end

  test "the search finds a server by one of its DNS names" do
    servers(:web).update!(extra_addresses_text: "203.0.113.10")
    Dns::Store.replace("ovh", [ { zone: "example.test", name: "shop.example.test", record_type: "A", value: "203.0.113.10" } ])
    sign_in users(:one)
    get servers_path(q: "shop.example")
    assert_select "#servers tbody tr", 1
    assert_select "#servers tbody tr", text: /Web/
  end
end
