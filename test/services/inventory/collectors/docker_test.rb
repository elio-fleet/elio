require "test_helper"

class Inventory::Collectors::DockerTest < ActiveSupport::TestCase
  include VulnerabilityHelpers

  Collector = Inventory::Collectors::Docker
  NOW = Time.zone.parse("2025-11-01 12:25")

  def output(name) = file_fixture("inventory/docker/#{name}.txt").read

  # Runs the collector against a fake server: the main command, then the scans.
  def collect(name, previous: nil, sudo: true, trivy: nil, packages: output(:image_packages), command_timeout: nil)
    known_hosts = Rails.root.join("tmp", "test", "docker-#{SecureRandom.hex(4)}", "known_hosts")
    handler = lambda do |command|
      if command.end_with?(Ssh::Commands.render("inventory.docker")) then FakeSsh::Response.new(output(name), "", 0)
      elsif command.include?("trivy image") then trivy || FakeSsh::Response.new(file_fixture("inventory/docker/trivy_report.json").read, "", 0)
      elsif command.include?("docker\\ cp") then FakeSsh::Response.new(packages, "", 0)
      end
    end
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", sudo ? 0 : 1) }, handler: handler)
    travel_to(NOW) do
      [ Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts, command_timeout: command_timeout) { |ssh| Collector.new(ssh, previous: previous).collect }, fake.commands ]
    end
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end

  test "reads the containers with their health, restarts and resources, never their environment" do
    data = Collector.parse(Collector.sections(output(:debian13)), now: NOW)
    containers = data["containers"].index_by { |container| container["name"] }

    assert_equal %w[web worker db backup-once], containers.keys
    assert_equal({ "id" => "3f4e5d6c7b8a", "name" => "web", "image" => "nginx:1.27", "image_id" => "sha256:#{"a" * 64}", "state" => "running", "restarts" => 0,
                   "health" => "healthy", "started_at" => "2025-10-20T10:00:00+02:00", "exit_code" => 0, "restart_policy" => "unless-stopped",
                   "created_at" => "2025-10-01T12:00:00+02:00", "project" => "shop", "service" => "web", "cpu_percent" => 0.15, "memory_bytes" => 13_107_200,
                   "memory_percent" => 0.63 }, containers["web"])
    assert containers["worker"]["looping"]
    assert_equal "unhealthy", containers["db"]["health"]
    assert containers["backup-once"]["stopped_long"]
    assert_not containers["web"].key?("looping")
    assert_not Ssh::Commands.render("inventory.docker").include?(".Config.Env"), "the environment (secrets) is never read"
  end

  test "reads the images (used or not, dangling ones without tag) and the disk usage" do
    data = Collector.parse(Collector.sections(output(:debian13)), now: NOW)
    images = data["images"].index_by { |image| image["id"].delete_prefix("sha256:").first }

    assert_equal [ [ "nginx:1.27" ], [ "nginx@sha256:#{"1" * 64}" ], true, 191_623_458, "2025-09-10T20:31:27+02:00" ],
                 images["a"].values_at("tags", "digests", "used", "size", "created_at")
    assert_equal [ [], false ], images["f"].values_at("tags", "used")
    assert_not images["e"]["used"]
    assert_equal({ "total" => 6, "active" => 4, "size" => 1_221_000_000, "reclaimable" => 228_000_000 }, data["disk"]["images"])
    assert_nil data["scanner"]
  end

  test "Docker absent, or unreadable without root" do
    assert_equal "unsupported", collect(:absent).first.status
    outcome, = collect(:unreadable, sudo: false)
    assert_equal [ "partial", "unreadable" ], [ outcome.status, outcome.data["docker"] ]
    assert_match "permission denied", outcome.message
    assert_match "Elio a besoin de root", outcome.message
  end

  test "without a scanner, Elio matches the packages of one container per image with the feeds" do
    record_os(servers(:db))
    load_debian_feed
    outcome, commands = collect(:debian13)

    assert_equal "ok", outcome.status
    scans = outcome.data["scans"]
    assert_equal [ "elio", 3, { "id" => "debian", "codename" => "bookworm", "version_id" => "12", "name" => "Debian GNU/Linux 12 (bookworm)" } ],
                 scans["sha256:#{"a" * 64}"].values_at("method", "count", "os")
    assert_equal "none", scans["sha256:#{"e" * 64}"]["method"], "no container to copy the packages from"
    assert_equal 4, commands.count { |command| command.include?("docker\\ cp") }, "one per image with a container"
    assert_includes commands, "sudo -n #{Ssh::Commands.render("inventory.docker_image_packages", container: "3f4e5d6c7b8a")}"
    rows = outcome.data["image_vulnerabilities"]["sha256:#{"a" * 64}"]
    assert_equal [ "nginx:1.27", "debian" ], rows.values_at("image", "source")
    assert_equal %w[CVE-2023-44487 CVE-2024-5535 CVE-2024-9143], rows["rows"].map { |row| row["cve"] }.sort,
                 "openssh only has config files left; glibc 2.36-9+deb12u10 is fixed"
  end

  test "the feed of the image must be downloaded first" do
    outcome, = collect(:debian13)
    assert_equal "bookworm pas encore dans la base Debian Security Tracker (prochaine mise à jour des vulnérabilités)", outcome.data["scans"]["sha256:#{"a" * 64}"]["error"]
  end

  test "with Trivy, scans each image, once a day, and keeps the rows of the others" do
    outcome, commands = collect(:with_trivy)
    assert_equal 6, commands.count { |command| command.include?("trivy image") }, "every image, used or not"
    assert_includes commands, "sudo -n trivy image --quiet --format json --scanners vuln nginx:1.27"
    assert_equal [ "trivy", 3, { "id" => "alpine", "version_id" => "3.20.3" } ], outcome.data["scans"]["sha256:#{"b" * 64}"].values_at("method", "count", "os")
    rows = outcome.data["image_vulnerabilities"]["sha256:#{"b" * 64}"]["rows"]
    assert_equal [ [ "GHSA-vvfq-8hwr-qm4m", "rack", "3.0.9.1", "critical" ], [ "CVE-2024-9143", "libcrypto3", "3.3.2-r1", "low" ], [ "CVE-2024-6119", "libssl3", nil, "high" ] ],
                 rows.map { |row| row.values_at("cve", "source_package", "fixed_version", "severity") }.sort_by { |row| row[0] }.reverse

    again, commands = collect(:with_trivy, previous: outcome.data)
    assert_equal 0, commands.count { |command| command.include?("trivy image") }
    assert again.data["scans"]["sha256:#{"b" * 64}"]["kept"]
  end

  test "a failed or too long scan is noted on the image" do
    outcome, = collect(:with_trivy, trivy: FakeSsh::Response.new("", "FATAL image scan error: unable to find the specified image", 1))
    assert_match "unable to find the specified image", outcome.data["scans"]["sha256:#{"a" * 64}"]["error"]

    outcome, = collect(:with_trivy, trivy: FakeSsh::Response.new("", "", 0, true), command_timeout: 0.2)
    scans = outcome.data["scans"].values
    assert_equal 1, scans.count { |scan| scan["session_lost"] }, "the session is lost: no other scan"
    assert_equal 5, scans.count { |scan| scan["method"] == "none" }
  end

  test "Grype reports" do
    rows, os = Collector.parse_grype(file_fixture("inventory/docker/grype_report.json").read)
    assert_equal [ [ "CVE-2024-6119", "libssl3", "3.3.2-r1", "high" ], [ "CVE-2023-0001", "busybox", nil, "low" ] ], rows.map { |row| row.values_at(:cve, :source_package, :fixed_version, :severity) }
    assert_equal({ "id" => "alpine", "version_id" => "3.20.3" }, os)
  end

  test "records the image rows image by image, and logs new serious ones after the first collection" do
    record_os(servers(:web))
    load_debian_feed
    AppSetting.current.update!(vulnerability_alert_severity: "any")
    outcome, = collect(:debian13)
    Collector.record(servers(:web), outcome.data.as_json, NOW)

    assert_equal 3, servers(:web).server_vulnerabilities.images.where(image: "nginx:1.27").count
    assert_equal [ "image", "debian" ], servers(:web).server_vulnerabilities.images.pick(:origin, :source)
    assert_equal 0, Activity.of_kind(:vulnerability_found).count, "first Docker collection"

    servers(:web).server_vulnerabilities.images.where(cve: "CVE-2024-9143").delete_all
    again, = collect(:debian13, previous: Collector.snapshot_data(outcome.data.as_json))
    Collector.record(servers(:web), again.data.as_json, NOW)
    assert_match "sur l'image nginx:1.27 de « Web » : CVE-2024-9143", Activity.of_kind(:vulnerability_found).first.summary
  end

  test "logs the containers that become unhealthy or start looping" do
    data = Collector.parse(Collector.sections(output(:debian13)), now: NOW)
    assert_equal [ { kind: :container_unhealthy, data: { container: "db" } }, { kind: :container_restarting, data: { container: "worker" } } ],
                 Collector.changes({ "containers" => [] }, data)
    assert_empty Collector.changes(data, data)
  end

  test "a container outside compose: Docker 26 prints <no value> for the missing labels" do
    line = "74d64c3fc8ab0000\t/coolify-sentinel\tdocker.io/coollabsio/sentinel:1.1.3\tsha256:95683c70\trunning\t0\thealthy\t2026-11-13T17:14:04Z\t0001-01-01T00:00:00Z\t0\tunless-stopped\t2026-11-13T17:14:04Z\t<no value>\t<no value>\n"
    container = Collector.parse_containers(line, now: NOW).sole

    assert_equal "coolify-sentinel", container["name"]
    assert_nil container["project"]
    assert_nil container["service"]
  end

  test "real output of DB-3 (Docker 26, Debian 13): containers without health check are listed too" do
    data = Collector.parse(Collector.sections(output(:"debian13-real")), now: Time.zone.parse("2026-11-01 13:22:30"))
    containers = data["containers"].index_by { |container| container["name"] }

    assert_equal %w[api backup-once web worker], containers.keys.sort
    assert_equal [ "running", "unhealthy", "shop", "api" ], containers["api"].values_at("state", "health", "project", "service")
    assert_equal [ "exited", nil, 0 ], containers["backup-once"].values_at("state", "health", "exit_code")
    assert_equal [ "restarting", true, "always" ], containers["worker"].values_at("state", "looping", "restart_policy")
    assert_equal %w[alpine:3.20 debian:12-slim nginx:1.27 redis:7], data["images"].map { |image| image["tags"].first }.sort
    assert_equal [ false ], data["images"].select { |image| image["tags"] == [ "redis:7" ] }.map { |image| image["used"] }
    assert_equal 4, data["disk"]["images"]["total"]
    assert_not_includes output(:"debian13-real"), "ne-doit-pas-sortir", "the environment of the worker (SECRET_TOKEN) is not read"
  end
end
