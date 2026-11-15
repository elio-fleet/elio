require "test_helper"

class AttentionListTest < ActiveSupport::TestCase
  def list
    servers = Server.order(:name).includes(:inventory_snapshots).to_a
    AttentionList.new(servers, insights: KeyInsights.new, summary: FleetSummary.new(servers))
  end

  test "unreachable servers and health concerns, the most serious first" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:db).update_columns(reachable: false)
    servers(:web).update_columns(health_status: "warn", health_reasons: [ { "tone" => "warn", "text" => "Redémarrage requis" }, { "tone" => "warn", "text" => "Horloge non synchronisée" } ])

    items = list.items

    assert_equal [ [ "crit", "Database", "Ne répond plus sur son port SSH" ], [ "warn", "Web", "Redémarrage requis (+1)" ] ],
                 items.map { |item| [ item.tone, item.subject, item.text ] }
  end

  test "pending security updates, as one item for the fleet" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", data: { "updates" => { "total" => 3, "security" => 2 } },
                                              collected_at: Time.current, checked_at: Time.current)

    item = list.items.sole
    assert_equal [ "warn", "1 serveur", "2 mises à jour de sécurité en attente", "/updates" ], [ item.tone, item.subject, item.text, item.path ]
  end

  test "Docker apart: the servers whose Docker is to watch or critical, never in the main list" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:web).update_columns(docker_status: "crit", docker_reasons: [ Inventory::HealthStatus.reason("crit", :container_looping, name: "worker").to_h,
                                                                           Inventory::HealthStatus.reason("warn", :images_to_update, count: 1).to_h ])
    servers(:db).update_columns(docker_status: "ok", docker_reasons: [])

    attention = list
    assert_empty attention.items
    item = attention.docker_items.sole
    assert_equal [ "crit", :docker, "Web", "Conteneur worker redémarre en boucle (+1)", "Voir Docker" ], [ item.tone, item.icon, item.subject, item.text, item.action ]
    assert_equal [ true, 1 ], [ attention.any?, attention.size ]
  end

  test "each item names its action and the servers it is about" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:web).update_columns(health_status: "crit", health_reasons: [ Inventory::HealthStatus.reason("crit", :disk, percent: 94, mount: "/").to_h ])
    servers(:db).update_columns(health_status: "warn", health_reasons: [ Inventory::HealthStatus.reason("warn", "integrations.uptime_kuma.health.no_monitor").to_h ])
    servers(:backup).update_columns(health_status: "warn", health_reasons: [ Inventory::HealthStatus.reason("warn", :reboot_required).to_h ])

    actions = list.items.to_h { |item| [ item.subject, [ item.action, item.path, item.servers ] ] }
    assert_equal [ "Voir les disques", "/servers/#{servers(:web).id}#disks", [ [ "Web", "/servers/#{servers(:web).id}" ] ] ], actions["Web"]
    assert_equal [ "Voir les sondes", "/servers/#{servers(:db).id}?tab=monitors" ], actions["Database"].first(2)
    assert_equal [ "Voir", "/servers/#{servers(:backup).id}" ], actions["Backup"].first(2)
  end

  test "by gravity, Docker included" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:web).update_columns(docker_status: "crit", docker_reasons: [ Inventory::HealthStatus.reason("crit", :container_looping, name: "worker").to_h ])
    servers(:db).update_columns(reachable: false)

    assert_equal({ "crit" => [ "Database", "Web" ] }, list.by_tone.transform_values { |items| items.map(&:subject) })
  end

  test "the fixable CVEs are one item for the fleet, not repeated on the line of each server" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    web, db = servers(:web), servers(:db)
    [ [ web, "host", nil ], [ db, "host", nil ], [ web, "image", "nginx:1.25" ] ].each_with_index do |(server, origin, image), index|
      ServerVulnerability.create!(server: server, origin: origin, image: image, source: "debian", cve: "CVE-2026-000#{index}", source_package: "openssl",
                                  installed_version: "1", fixed_version: "2", severity: "critical")
    end
    vulnerabilities = Inventory::HealthStatus.reason("crit", :vulnerabilities, count: 2).to_h
    web.update_columns(health_status: "crit", health_reasons: [ vulnerabilities, Inventory::HealthStatus.reason("warn", :reboot_required).to_h ],
                       docker_status: "warn", docker_reasons: [ Inventory::HealthStatus.reason("warn", :image_vulnerabilities, count: 1, images: 1).to_h ])
    db.update_columns(health_status: "crit", health_reasons: [ vulnerabilities ])

    attention = list
    assert_equal [ [ "2 serveurs", :shield_exclamation ], [ "Web", :exclamation_triangle ] ], attention.items.map { |item| [ item.subject, item.icon ] }
    assert_equal "Redémarrage requis", attention.items.last.text
    assert_equal [ "1 serveur" ], attention.docker_items.map(&:subject)
  end

  test "since when each problem of a server has been there, from the journal" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    reboot = Inventory::HealthStatus.reason("warn", :reboot_required).to_h
    servers(:web).update_columns(health_status: "warn", health_reasons: [ reboot ])
    servers(:db).update_columns(reachable: false)
    servers(:backup).update_columns(inventoried_at: nil, created_at: 4.days.ago)
    Activity.create!(kind: "health_warning", server: servers(:web), data: { reasons: [ reboot ] }, created_at: 3.days.ago)
    Activity.create!(kind: "server_unreachable", server: servers(:db), created_at: 2.hours.ago)

    since = list.items.to_h { |item| [ item.subject, item.since ] }
    assert_in_delta 3.days.ago, since["Web"], 1
    assert_in_delta 2.hours.ago, since["Database"], 1
    assert_in_delta 4.days.ago, since["Backup"], 1
  end

  test "a vulnerability reason opens the packages to update, where each one has its command" do
    server = servers(:web)
    _, path = AttentionList.action_for(server, Inventory::HealthStatus.reason("crit", :vulnerabilities, count: 2).to_h)
    assert_equal "/servers/#{server.id}?fixable=1&tab=vulnerabilities&view=packages", path
  end

  test "the fixable CVEs of a single server: straight to its fixes" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    ServerVulnerability.create!(server: servers(:web), origin: "host", source: "debian", cve: "CVE-2026-0001", source_package: "openssl",
                                installed_version: "1", fixed_version: "2", severity: "critical")

    item = list.items.sole
    assert_equal "Voir les correctifs", item.action
    assert_equal "/servers/#{servers(:web).id}?fixable=1&severity=#{AppSetting.current.vulnerability_alert_severity}&tab=vulnerabilities&view=packages", item.path
  end

  test "by gravity, the most serious first up to a limit; the counts cover everything" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    servers(:db).update_columns(reachable: false)
    servers(:web).update_columns(health_status: "warn", health_reasons: [ Inventory::HealthStatus.reason("warn", :reboot_required).to_h ])
    servers(:backup).update_columns(health_status: "warn", health_reasons: [ Inventory::HealthStatus.reason("warn", :reboot_required).to_h ])

    attention = list
    assert_equal({ "crit" => [ "Database" ], "warn" => [ "Backup" ] }, attention.by_tone(limit: 2).transform_values { |items| items.map(&:subject) })
    assert_equal({ "crit" => 1, "warn" => 2 }, attention.tone_counts)
  end

  test "nothing to report" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    assert_not list.any?
  end
end
