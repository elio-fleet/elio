require "test_helper"

class Inventory::Collectors::PackagesTest < ActiveSupport::TestCase
  Collector = Inventory::Collectors::Packages

  def output(name) = file_fixture("inventory/packages/#{name}.txt").read

  def collect(name, sudo: true, docker: FakeSsh::Response.new(output(:docker_images), "", 0))
    known_hosts = Rails.root.join("tmp", "test", "packages-#{SecureRandom.hex(4)}", "known_hosts")
    main = FakeSsh::Response.new(output(name), "", 0)
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", sudo ? 0 : 1) },
                       handler: ->(command) { command.start_with?("sh -c") ? main : (docker if command.include?("docker image ls")) })
    outcome = Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Collector.new(ssh).collect }
    [ outcome, fake.commands ]
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end

  test "lists the installed dpkg packages with their updates, and the Docker images through sudo" do
    outcome, commands = collect(:debian12)

    assert_equal "ok", outcome.status
    packages = outcome.data["packages"]
    dpkg = packages.select { |package| package["manager"] == "dpkg" }
    assert_equal %w[adduser curl libssl3 libssl3 linux-image-amd64 openssl postgresql-15], dpkg.map { |package| package["name"] }
    assert_equal({ "manager" => "dpkg", "name" => "openssl", "version" => "3.0.14-1~deb12u1", "arch" => "amd64",
                   "available_version" => "3.0.15-1~deb12u1", "security" => true, "origin" => "Debian/bookworm" }, dpkg.find { |package| package["name"] == "openssl" })
    assert_equal [ "7.88.1-10+deb12u8", false ], dpkg.find { |package| package["name"] == "curl" }.values_at("available_version", "security")
    assert_equal [ [ "nginx", "1.27-alpine" ], [ "postgres", "16" ], [ "ghcr.io/acme/api", "fedcba987654" ] ],
                 packages.select { |package| package["manager"] == "docker" }.map { |package| package.values_at("name", "version") }
    assert_equal({ "dpkg" => 7, "docker" => 3 }, outcome.data["by_manager"])
    assert_equal [ 10, 4, 3 ], outcome.data.values_at("total", "upgradable", "security")
    assert_includes commands, "sudo -n #{Ssh::Commands.render("inventory.docker_images")}"
  end

  test "Docker images that cannot be read make the collection partial" do
    outcome, = collect(:debian12, sudo: false, docker: FakeSsh::Response.new("", "permission denied while trying to connect to the Docker daemon socket", 1))

    assert_equal "partial", outcome.status
    assert_match "Images Docker illisibles : permission denied", outcome.message
    assert_equal 7, outcome.data["total"]
  end

  test "Ubuntu: snaps and security updates from -security suites" do
    outcome, commands = collect(:ubuntu2404)

    assert_equal [ [ "snap", "core22", "20240904" ], [ "snap", "lxd", "5.21.2" ] ],
                 outcome.data["packages"].select { |package| package["manager"] == "snap" }.map { |package| package.values_at("manager", "name", "version") }
    assert outcome.data["packages"].find { |package| package["name"] == "snapd" }["security"]
    assert_not commands.any? { |command| command.include?("docker image ls") }
  end

  test "a system without dpkg nor snap is unsupported" do
    outcome, = collect(:none)
    assert_equal [ "unsupported", "Ni dpkg ni snap sur ce système" ], [ outcome.status, outcome.message ]
  end

  test "the snapshot keeps the counts, not the list" do
    data = Collector.summarize([ { "manager" => "dpkg", "name" => "a" } ])
    assert_equal({ "total" => 1, "by_manager" => { "dpkg" => 1 }, "upgradable" => 0, "security" => 0 }, Collector.snapshot_data(data))
  end

  test "records the list, replaces it and logs the changes after the first time" do
    server = servers(:web)
    first = Collector.summarize([ { "manager" => "dpkg", "name" => "curl", "version" => "1", "arch" => "amd64" },
                                  { "manager" => "dpkg", "name" => "vim", "version" => "9", "arch" => "amd64" } ])
    assert_no_difference("Activity.count") { Collector.record(server, first, Time.current) }
    assert_equal %w[curl vim], server.packages.order(:name).pluck(:name)

    second = Collector.summarize([ { "manager" => "dpkg", "name" => "curl", "version" => "2", "arch" => "amd64", "available_version" => "3", "security" => true },
                                   { "manager" => "dpkg", "name" => "htop", "version" => "3", "arch" => "amd64" } ])
    Collector.record(server, second, Time.current)

    assert_equal [ [ "curl", "2", "3", true ], [ "htop", "3", nil, false ] ],
                 server.packages.order(:name).pluck(:name, :version, :available_version, :security)
    activity = Activity.of_kind(:packages_changed).sole
    assert_equal "Paquets de « Web » : 1 installé, 1 mis à jour, 1 supprimé (curl, htop, vim)", activity.summary
  end

  test "warns when security updates appear" do
    assert_equal [ { kind: :security_updates_available, data: { count: 3 } } ], Collector.changes({ "security" => 0 }, { "security" => 3 })
    assert_empty Collector.changes({ "security" => 2 }, { "security" => 3 })
    assert_empty Collector.changes({ "security" => 2 }, { "security" => 0 })
  end

  test "keeps the source package when it differs (vulnerability feeds), stored for every dpkg package" do
    text = "ii \tlibssl3\t3.0.14-1~deb12u1\tamd64\topenssl\t3.0.14-1~deb12u1\n" \
           "ii \tlibc6\t2.36-9+deb12u10+b1\tamd64\tglibc\t2.36-9+deb12u10\n" \
           "ii \tcurl\t7.88.1-10+deb12u12\tamd64\tcurl\t7.88.1-10+deb12u12\n"
    packages = Collector.parse_dpkg(text, {})

    assert_equal [ [ "openssl", nil ], [ "glibc", "2.36-9+deb12u10" ], [ nil, nil ] ], packages.map { |package| package.values_at("source", "source_version") }
    Collector.record(servers(:web), Collector.summarize(packages), Time.current)
    assert_equal [ [ "curl", "curl", "7.88.1-10+deb12u12" ], [ "libc6", "glibc", "2.36-9+deb12u10" ], [ "libssl3", "openssl", "3.0.14-1~deb12u1" ] ],
                 servers(:web).packages.order(:name).pluck(:name, :source_name, :source_version)
  end

  test "the repository of each dpkg package, and the last dpkg.log changes newest first" do
    outcome, = collect(:debian12)

    origins = outcome.data["packages"].select { |package| package["manager"] == "dpkg" }.to_h { |package| [ package.values_at("name", "arch").join(":"), package["origin"] ] }
    assert_equal({ "adduser:all" => "Debian/bookworm", "curl:amd64" => "Debian/bookworm", "libssl3:amd64" => "Debian/bookworm-security",
                   "libssl3:i386" => "Debian/bookworm", "linux-image-amd64:amd64" => "Debian Backports/bookworm-backports",
                   "openssl:amd64" => "Debian/bookworm", "postgresql-15:amd64" => "apt.example.org/bookworm-pgdg" }, origins)
    history = outcome.data["history"]
    assert_equal [ "2024-09-11 09:12:40", "remove", "old-package", "1.0", nil ], history.first.values_at("at", "action", "name", "from", "to")
    assert_equal [ "install", "postgresql-15", nil, "15.7-1.pgdg120+1" ], history.last.values_at("action", "name", "from", "to")
    assert_equal history, Collector.snapshot_data(outcome.data)["history"]

    Collector.record(servers(:web), outcome.data, Time.current)
    assert_equal "apt.example.org/bookworm-pgdg", servers(:web).packages.find_by(name: "postgresql-15").origin
  end

  test "a package no repository provides is local; without origins nothing is guessed" do
    origins = Collector.parse_origins("@1\thttp://deb.debian.org/debian bookworm/main amd64 Packages\nelio-tool\t\ncurl\t1\n", "")
    assert_equal({ "elio-tool" => "local", "curl" => "deb.debian.org/bookworm" }, origins)
    assert_empty Collector.parse_origins("", "")
    assert_nil Collector.parse_dpkg("ii \tcurl\t1\tamd64\n", {}).sole["origin"]
  end

  test "the origins script reads apt-cache policy for real (awk) and keeps one short line per package" do
    Dir.mktmpdir do |dir|
      fixtures = file_fixture("inventory/packages")
      { "dpkg-query" => 'echo "$*" | grep -q binary: && printf "ii  adduser\\nii  curl\\nrc  gone\\n"',
        "apt-cache" => "if [ $# -eq 1 ]; then cat '#{fixtures.join("apt-cache-policy.txt")}'; else cat '#{fixtures.join("apt-cache-policy-installed.txt")}'; fi",
        "apt" => "true" }.each do |name, body|
        File.write(File.join(dir, name), "#!/bin/sh\n#{body}\n")
        File.chmod(0o755, File.join(dir, name))
      end
      script = Ssh::Commands.fetch("inventory.packages").template(%w[debian])
      stdout, status = Open3.capture2({ "PATH" => "#{dir}:#{ENV["PATH"]}" }, "sh", "-c", script)
      assert status.success?

      sections = Collector.sections(stdout)
      assert_includes sections["sources"].lines, "http://deb.debian.org/debian bookworm/main amd64 Packages\tv=12.7,o=Debian,a=stable,n=bookworm,l=Debian,c=main,b=amd64\n"
      assert_equal({ "adduser" => "Debian/bookworm", "curl" => "Debian/bookworm", "libssl3" => "Debian/bookworm", "libssl3:i386" => "Debian/bookworm",
                     "linux-image-amd64" => "Debian Backports/bookworm-backports", "docker-ce" => "Docker/bookworm", "elio-tool" => "local" },
                   Collector.parse_origins(sections["origins"], sections["sources"]))
    end
  end
end
