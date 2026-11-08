require "test_helper"

class SidebarCountsTest < ActiveSupport::TestCase
  setup { Server.update_all(docker_status: nil, health_reasons: []) }

  test "servers: the total, never coloured" do
    assert_equal SidebarCounts::Count.new(Server.count, nil), SidebarCounts.new.servers
  end

  test "vulnerabilities: the distinct fixable CVEs of the servers from the alert severity, in red" do
    ServerVulnerability.delete_all
    [ servers(:web), servers(:backup) ].each do |server|
      server.server_vulnerabilities.create!(origin: "host", source: "debian", cve: "CVE-2024-6387", source_package: "openssh", installed_version: "1", fixed_version: "2", severity: "high")
    end
    servers(:web).server_vulnerabilities.create!(origin: "host", source: "debian", cve: "CVE-2024-1", source_package: "x", installed_version: "1", fixed_version: nil, severity: "critical")
    servers(:web).server_vulnerabilities.create!(origin: "image", source: "debian", image: "nginx:1", cve: "CVE-2024-2", source_package: "y", installed_version: "1", fixed_version: "2", severity: "critical")

    assert_equal SidebarCounts::Count.new(1, :crit), SidebarCounts.new.vulnerabilities
    assert_nil SidebarCounts.new(settings: AppSetting.current.tap { |s| s.vulnerability_alert_severity = "none" }).vulnerabilities
  end

  test "vulnerabilities: nothing when there is none" do
    ServerVulnerability.delete_all
    assert_nil SidebarCounts.new.vulnerabilities
  end

  test "docker: critical servers in red first, else the servers to watch in orange" do
    assert_nil SidebarCounts.new.docker
    servers(:web).update_columns(docker_status: "warn")
    assert_equal SidebarCounts::Count.new(1, :warn), SidebarCounts.new.docker
    servers(:backup).update_columns(docker_status: "crit")
    assert_equal SidebarCounts::Count.new(1, :crit), SidebarCounts.new.docker
  end

  test "scheduled tasks: the servers with a failed or late timer, in orange" do
    assert_nil SidebarCounts.new.scheduled_tasks
    servers(:web).update_columns(health_reasons: [ { "tone" => "warn", "key" => "health.timer_failed", "params" => { "name" => "certbot" } } ])
    servers(:backup).update_columns(health_reasons: [ { "tone" => "warn", "key" => "health.reboot_required", "params" => {} } ])

    assert_equal SidebarCounts::Count.new(1, :warn), SidebarCounts.new.scheduled_tasks
  end
end
