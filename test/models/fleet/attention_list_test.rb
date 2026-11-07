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

  test "nothing to report" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current)
    assert_not list.any?
  end
end
