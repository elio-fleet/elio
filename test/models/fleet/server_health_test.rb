require "test_helper"

class ServerHealthTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    @server.update_columns(ssh_ok: true, reachable: true)
  end

  def collect_health(**data)
    snapshot = @server.inventory_snapshots.find_or_initialize_by(category: "health")
    snapshot.update!(status: "ok", data: { "load" => [ 0.1 ], "cpus" => 2, "disks" => [] }.merge(data.stringify_keys),
                     collected_at: Time.current, checked_at: Time.current)
    @server.refresh_health!
  end

  test "stores the state and its reasons, without activity the first time" do
    assert_no_difference("Activity.count") { collect_health(reboot_required: true) }

    assert_equal "warn", @server.health_status
    assert_equal [ "Redémarrage requis" ], @server.health_reason_texts
    assert_equal "warn", @server.health_state
  end

  test "logs when the state gets worse, becomes critical or recovers, not when it stays the same" do
    collect_health

    assert_difference("Activity.of_kind(:health_warning).count") { collect_health(reboot_required: true) }
    assert_no_difference("Activity.count") { collect_health(reboot_required: true) }
    assert_difference("Activity.of_kind(:health_critical).count") do
      collect_health(disks: [ { "mount" => "/", "used_percent" => 97 } ])
    end
    assert_equal "« Web » est en état critique : Disque / à 97\u00A0%", Activity.of_kind(:health_critical).sole.summary
    assert_difference("Activity.of_kind(:health_recovered).count") { collect_health }
    assert_equal "critical", Activity::KINDS.fetch(:health_critical).severity.to_s
  end

  test "an unreachable server is shown off, whatever its inventory" do
    collect_health
    @server.update_columns(reachable: false)

    assert_equal [ "ok", "off" ], [ @server.health_status, @server.health_state ]
    assert_equal "unknown", Server.new.health_state
  end

  test "a refused key recomputes the health of an inventoried server" do
    collect_health

    @server.record_ssh_status!(false)

    assert_equal [ "crit", [ "Clé Elio refusée : inventaire impossible" ] ], [ @server.health_status, @server.health_reason_texts ]
    assert Activity.of_kind(:health_critical).exists?
  end

  def collect_docker(**container)
    snapshot = @server.inventory_snapshots.find_or_initialize_by(category: "docker")
    snapshot.update!(status: "ok", collected_at: Time.current, checked_at: Time.current,
                     data: { "docker" => "ok", "images" => [], "containers" => [ { "name" => "web", "state" => "running" }.merge(container.stringify_keys) ] })
    @server.refresh_health!
  end

  test "the CVEs of the Docker images never change the health of the server" do
    collect_health
    @server.server_vulnerabilities.create!(origin: "image", source: "debian", image: "nginx:1.27", cve: "CVE-2024-45491", source_package: "expat",
                                           packages: [ "libexpat1" ], installed_version: "2.5.0-1", fixed_version: "2.5.0-1+deb12u1", severity: "critical")
    collect_docker

    assert_equal [ "ok", "warn" ], [ @server.health_status, @server.docker_status ]
    assert_equal [ "1 vulnérabilité grave corrigeable dans les images Docker" ], @server.docker_reason_texts
  end

  test "no Docker state without a readable Docker, and no activity the first time" do
    collect_health
    assert_nil @server.docker_status

    assert_no_difference("Activity.count") { collect_docker }
    assert_equal "ok", @server.docker_status
  end

  test "logs the changes of the Docker state apart from the health" do
    collect_health
    collect_docker

    assert_difference("Activity.of_kind(:docker_critical).count") { collect_docker(looping: true) }
    assert_equal "Docker de « Web » est en état critique : Conteneur web redémarre en boucle", Activity.of_kind(:docker_critical).sole.summary
    assert_equal "ok", @server.health_status
    assert_no_difference("Activity.count") { collect_docker(looping: true) }
    assert_difference("Activity.of_kind(:docker_recovered).count") { collect_docker }
    assert_equal 0, Activity.where(kind: %w[health_warning health_critical]).count
  end
end
