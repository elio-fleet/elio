require "test_helper"

class ServerServicesCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def collect(data, status: "ok", message: nil)
    servers(:web).inventory_snapshots.create!(category: "services", status: status, data: data, message: message, collected_at: Time.current, checked_at: Time.current)
  end

  def parsed
    sections = Inventory::Collectors::Services.sections(file_fixture("inventory/services/debian12.txt").read)
    units = Inventory::Collectors::Services.parse_units(sections["units"], Inventory::Collectors::Services.parse_unit_details(sections["unit-details"]))
    containers = Inventory::Collectors::Services.parse_containers(file_fixture("inventory/services/docker_ps.txt").read)
    { "units" => units, "containers" => containers, "docker" => "ok" }
  end

  test "shows the failed units first, the stopped ones that start at boot apart, folds the other inactive ones" do
    collect(parsed)
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select "#server-services" do
      assert_select ".services-summary", text: /4 services actifs\s+· 1 en échec\s+· 3 inactifs\s+· 2\/3 conteneurs en cours/
      assert_select ".systemd-units > ul li.systemd-unit:first-child[data-state=failed]", text: /en échec\s+fail2ban/
      assert_select ".systemd-units > ul li.systemd-unit", 5
      assert_select ".services-stopped h4", "Lancé au démarrage mais arrêté (1)"
      assert_select ".services-stopped li.systemd-unit", 1 do
        assert_select "li", text: /arrêté\s+nginx\s+au démarrage\s+arrêté il y a/
      end
      assert_select ".systemd-units details li.systemd-unit", 2 # apt-daily (one-shot), unattended-upgrades (not at boot)
      assert_select "li.systemd-unit", text: /actif\s+ssh\s+au démarrage\s+démarré il y a/
      assert_select "li.systemd-unit[data-state=inactive]", text: /inactif\s+apt-daily/
      assert_select "li.docker-container", 0 # in the Docker tab
      assert_select ".services-docker-link a[href=?]", server_path(servers(:web), tab: "docker"), text: /onglet Docker/
    end
  end

  test "filters by state and searches the name and the description, the counts following the search" do
    collect(parsed)
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select ".services-filters .filter-chip[aria-current=true]", text: /Tous\s+8/
    assert_select ".services-filters .filter-chip[data-state=inactive][href=?]", server_path(servers(:web), tab: "services", state: "inactive"), text: /Inactifs\s+3/
    assert_select "form.services-search[data-turbo-frame=services-results] input[type=hidden][name=tab][value=services]"
    assert_select "turbo-frame#services-results .systemd-units"

    get server_path(servers(:web), tab: "services", state: "inactive")

    assert_select "li.systemd-unit", 3
    assert_select ".services-stopped li.systemd-unit", text: /nginx/
    assert_select ".services-inactive li.systemd-unit", 2 # unfolded once filtered
    assert_select ".systemd-units details", 0
    assert_select "form.services-search input[type=hidden][name=state][value=inactive]"

    get server_path(servers(:web), tab: "services", state: "failed")
    assert_select "li.systemd-unit", 1
    assert_select "li.systemd-unit[data-state=failed]", text: /fail2ban/

    get server_path(servers(:web), tab: "services", q: "  SHELL ")

    assert_select "li.systemd-unit", 1
    assert_select "li.systemd-unit", text: /ssh\s.*OpenBSD Secure Shell server/m
    assert_select "input[name=q][value=SHELL]"
    assert_select ".services-filters .filter-chip[data-state=active][href=?]", server_path(servers(:web), tab: "services", state: "active", q: "SHELL"), text: /Actifs\s+1/
    assert_select ".services-filters .filter-chip[data-state=failed]", text: /En échec\s+0/
    assert_select ".services-summary", text: /4 services actifs/, message: "the summary stays the whole server's"

    get server_path(servers(:web), tab: "services", state: "failed", q: "nginx")
    assert_select ".systemd-units .empty-state", text: /Aucun service ne correspond à ces filtres/
    assert_select ".empty-state a[href=?]", server_path(servers(:web), tab: "services")
  end

  test "a unit read before the type was is not taken for a stopped one" do
    collect({ "units" => [ { "name" => "e2scrub_reap.service", "active" => "inactive", "sub" => "dead", "enabled" => "enabled" } ] })
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select ".services-stopped", 0
    assert_select "details li.systemd-unit", text: /inactif\s+e2scrub_reap/
  end

  test "the health reading adds since when a unit failed, and the failed units the services inventory does not list" do
    collect(parsed)
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "failed_units" => %w[fail2ban.service mnt-backup.mount],
                                                      "failed_units_details" => [ { "name" => "fail2ban.service", "since" => 2.hours.ago.utc.iso8601 },
                                                                                  { "name" => "mnt-backup.mount", "description" => "Backup share", "since" => 3.hours.ago.utc.iso8601 } ] })
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select "#server-services" do
      assert_select ".services-summary", text: /· 2 en échec/
      assert_select "li.systemd-unit[data-state=failed]", 2
      assert_select "li.systemd-unit[data-state=failed]", text: /fail2ban.*a échoué il y a 2 heures/m
      assert_select "li.systemd-unit[data-state=failed]", text: /mnt-backup\.mount.*a échoué il y a 3 heures.*vu au relevé de santé.*Backup share/m
    end
    assert_select "a.tab", text: /Services\s*2/
  end

  test "a failed unit opens on its journal (read when opened) and the command to restart it; a unit failed at startup says so" do
    servers(:web).inventory_snapshots.create!(category: "os", status: "ok", collected_at: Time.current, checked_at: Time.current, data: { "booted_at" => 3.days.ago.utc.iso8601 })
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "failed_units" => %w[mnt-backup.mount nginx.service],
                                                      "failed_units_details" => [ { "name" => "mnt-backup.mount", "since" => (3.days.ago + 40.seconds).utc.iso8601 },
                                                                                  { "name" => "nginx.service", "since" => 2.hours.ago.utc.iso8601 } ] })
    sign_in users(:operator)

    get server_path(servers(:web), tab: "services")

    assert_select "li.systemd-unit[data-state=failed]", text: /mnt-backup\.mount.*a échoué au démarrage du serveur \(il y a 3 jours\)/m
    assert_select "li.systemd-unit[data-state=failed]", text: /nginx.*a échoué il y a 2 heures/m
    assert_select "li.systemd-unit[data-state=failed] details.unit-journal", 2
    assert_select "details.unit-journal summary", text: "Journal et commande de relance", count: 2
    assert_select "details.unit-journal .unit-restart code", text: "sudo systemctl restart nginx.service"
    assert_select "details.unit-journal turbo-frame[loading=lazy][src=?]", server_unit_journal_path(servers(:web), unit: "nginx.service")

    sign_in users(:viewer)
    get server_path(servers(:web), tab: "services")

    assert_select "details.unit-journal summary", text: "Commande de relance", count: 2
    assert_select "details.unit-journal .unit-restart code", text: "sudo systemctl restart nginx.service"
    assert_select "details.unit-journal turbo-frame", 0
  end

  test "without a services inventory, the failed units of the health reading are listed anyway" do
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "failed_units" => %w[mnt-archive.mount] })
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select "#server-services li.systemd-unit[data-state=failed]", text: /mnt-archive\.mount.*vu au relevé de santé/m
    assert_select "#server-services .services-empty", "Pas encore d'inventaire des services."
  end

  test "explains unreadable containers" do
    collect(parsed.merge("docker" => "unreadable", "containers" => []), status: "partial", message: "Conteneurs Docker illisibles : permission denied")
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select "#server-services .services-docker-link a[href=?]", server_path(servers(:web), tab: "docker")
  end

  test "before any inventory" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "services")
    assert_select "#server-services .services-empty", "Pas encore d'inventaire des services."
  end
end
