require "test_helper"

class Inventory::Collectors::ServicesTest < ActiveSupport::TestCase
  Collector = Inventory::Collectors::Services

  def output(name) = file_fixture("inventory/services/#{name}.txt").read

  def collect(name, docker: FakeSsh::Response.new(output(:docker_ps), "", 0), sudo: true)
    known_hosts = Rails.root.join("tmp", "test", "services-#{SecureRandom.hex(4)}", "known_hosts")
    main = FakeSsh::Response.new(output(name), "", 0)
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", sudo ? 0 : 1) },
                       handler: ->(command) { command.start_with?("sh -c") ? main : (docker if command.include?("docker ps")) })
    [ Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Collector.new(ssh).collect }, fake.commands ]
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end

  test "lists the systemd units with their boot state, and the containers through sudo" do
    outcome, commands = collect(:debian12)

    assert_equal "ok", outcome.status
    units = outcome.data["units"]
    assert_equal 7, units.size
    assert_equal({ "name" => "fail2ban.service", "load" => "loaded", "active" => "failed", "sub" => "failed",
                   "description" => "Fail2Ban Service", "enabled" => "enabled" }, units.find { |unit| unit["name"] == "fail2ban.service" })
    assert_equal "disabled", units.find { |unit| unit["name"] == "unattended-upgrades.service" }["enabled"]
    assert_not units.find { |unit| unit["name"] == "postgresql@15-main.service" }.key?("enabled")

    containers = outcome.data["containers"]
    assert_equal({ "id" => "0123456789ab", "name" => "pgbouncer", "image" => "edoburu/pgbouncer:1.23", "state" => "running", "status" => "Up 3 days",
                   "ports" => "0.0.0.0:6432->6432/tcp, :::6432->6432/tcp", "project" => "ops-tools", "working_dir" => "/opt/ops-tools",
                   "config_files" => [ "/opt/ops-tools/compose.yml", "/opt/ops-tools/compose.prod.yml" ], "service" => "pgbouncer" }, containers.first)
    assert_equal({ "id" => "aaaabbbbcccc", "name" => "backup-once", "image" => "alpine:3.20", "state" => "exited", "status" => "Exited (0) 2 days ago" }, containers.last)
    assert_equal "ok", outcome.data["docker"]
    assert_includes commands, "sudo -n #{Ssh::Commands.render("inventory.docker_containers")}"
  end

  test "the container state comes from the status, which every Docker version prints" do
    { "Up 3 days" => "running", "Up 12 minutes (healthy)" => "running", "Up About an hour (unhealthy)" => "running",
      "Up 5 minutes (Paused)" => "paused", "Restarting (1) 4 seconds ago" => "restarting", "Exited (137) 2 weeks ago" => "exited",
      "Created" => "created", "Removal In Progress" => "removing", "Dead" => "dead", "" => nil, "Something new" => nil }.each do |status, state|
      state ? assert_equal(state, Inventory::Collectors::Services.state(status), status.inspect) : assert_nil(Inventory::Collectors::Services.state(status), status.inspect)
    end
  end

  test "the command never asks for {{.State}}: Docker before 20.10 refuses the whole format" do
    assert_not_includes Ssh::Commands.render("inventory.docker_containers"), ".State"
  end

  test "unreadable containers make the collection partial" do
    outcome, = collect(:debian12, sudo: false, docker: FakeSsh::Response.new("", "permission denied while trying to connect to the Docker daemon socket", 1))

    assert_equal [ "partial", "unreadable", 7 ], [ outcome.status, outcome.data["docker"], outcome.data["units"].size ]
    assert_match "Conteneurs Docker illisibles", outcome.message
  end

  test "a system without systemd nor Docker is unsupported" do
    outcome, = collect(:none)
    assert_equal "unsupported", outcome.status
  end

  test "logs failed and recovered services, stopped and restarted containers" do
    unit = ->(name, active) { { "name" => name, "active" => active } }
    container = ->(name, state) { { "name" => name, "state" => state } }
    previous = { "units" => [ unit.("a.service", "active"), unit.("b.service", "failed"), unit.("gone.service", "failed") ],
                 "containers" => [ container.("web", "running"), container.("job", "exited") ], "docker" => "ok" }
    data = { "units" => [ unit.("a.service", "failed"), unit.("b.service", "active") ],
             "containers" => [ container.("web", "exited"), container.("job", "running"), container.("new", "running") ], "docker" => "ok" }

    assert_equal [ { kind: :service_failed, data: { service: "a.service" } }, { kind: :service_recovered, data: { service: "b.service" } },
                   { kind: :container_stopped, data: { container: "web" } }, { kind: :container_started, data: { container: "job" } } ],
                 Collector.changes(previous, data)
  end

  test "unreadable containers are not reported as stopped" do
    previous = { "units" => [], "containers" => [ { "name" => "web", "state" => "running" } ], "docker" => "ok" }
    assert_empty Collector.changes(previous, { "units" => [], "containers" => [], "docker" => "unreadable" })
  end
end
