require "test_helper"

class ServerServicesCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def collect(data, status: "ok", message: nil)
    servers(:web).inventory_snapshots.create!(category: "services", status: status, data: data, message: message, collected_at: Time.current, checked_at: Time.current)
  end

  def parsed
    units = Inventory::Collectors::Services.parse_units(file_fixture("inventory/services/debian12.txt").read.split("@@elio unit-files").first.sub("@@elio units\n", ""),
                                                        { "ssh.service" => "enabled" })
    containers = Inventory::Collectors::Services.parse_containers(file_fixture("inventory/services/docker_ps.txt").read)
    { "units" => units, "containers" => containers, "docker" => "ok" }
  end

  test "shows the failed units first, folds the inactive ones, and groups the containers by Compose project" do
    collect(parsed)
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "services")

    assert_select "#server-services" do
      assert_select ".services-summary", text: /4 services actifs\s+· 1 en échec\s+· 2 inactifs\s+· 2\/3 conteneurs en cours/
      assert_select ".systemd-units > ul li.systemd-unit:first-child[data-state=failed]", text: /en échec\s+fail2ban/
      assert_select ".systemd-units > ul li.systemd-unit", 5
      assert_select ".systemd-units details li.systemd-unit", 2
      assert_select "li.systemd-unit", text: /ssh\s+au démarrage/
      assert_select "li.docker-container", 0 # in the Docker tab
      assert_select ".services-docker-link a[href=?]", server_path(servers(:web), tab: "docker"), text: /onglet Docker/
    end
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
