require "test_helper"

class Vulnerabilities::FixCommandsTest < ActiveSupport::TestCase
  include PackageHelpers
  include VulnerabilityHelpers

  def row(server, cve:, source_package:, packages:, installed:, fixed:, origin: "host", image: nil, severity: "high")
    server.server_vulnerabilities.create!(origin: origin, source: "debian", image: image, cve: cve, source_package: source_package, packages: packages,
                                          installed_version: installed, fixed_version: fixed, severity: severity)
  end

  def plans(server, rows) = Vulnerabilities::FixCommands.new(server, rows).plans

  test "a fix offered by the repositories: one apt command for every binary of the source, with sudo when not root" do
    server = servers(:web) # deploy
    record_packages(server, [ dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl").merge("available_version" => "3.0.15-1~deb12u1"),
                              dpkg("openssl", "3.0.14-1~deb12u1").merge("available_version" => "3.0.15-1~deb12u1") ])
    vulnerability = row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1")

    plan = plans(server, [ vulnerability ]).sole
    assert plan.host?
    assert_equal :available, plan.state
    assert_equal [ "sudo apt-get install --only-upgrade libssl3 openssl" ], plan.commands
    assert_not plan.reboot
  end

  test "a fix the server has not seen yet: refresh the package lists first; root needs no sudo" do
    server = servers(:backup) # root
    record_packages(server, [ dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh") ])
    vulnerability = row(server, cve: "CVE-2024-6387", source_package: "openssh", packages: [ "openssh-server" ], installed: "1:9.2p1-2+deb12u2", fixed: "1:9.2p1-2+deb12u3")

    plan = plans(server, [ vulnerability ]).sole
    assert_equal :pending, plan.state
    assert_equal [ "apt-get update", "apt-get install --only-upgrade openssh-server" ], plan.commands
  end

  test "the kernel needs a reboot" do
    server = servers(:backup)
    record_packages(server, [ dpkg("linux-image-6.1.0-25-amd64", "6.1.106-3", source: "linux").merge("available_version" => "6.1.112-1") ])
    vulnerability = row(server, cve: "CVE-2024-1", source_package: "linux", packages: [ "linux-image-6.1.0-25-amd64" ], installed: "6.1.106-3", fixed: "6.1.112-1")

    plan = plans(server, [ vulnerability ]).sole
    assert plan.reboot
    assert_equal [ "apt-get install --only-upgrade linux-image-6.1.0-25-amd64" ], plan.commands, "the reboot is a note, never in the block to paste"
  end

  test "the fixed kernel already installed: a reboot, nothing to install" do
    server = servers(:backup)
    record_packages(server, [ dpkg("linux-image-6.1.0-25-amd64", "6.1.106-3", source: "linux"), dpkg("linux-image-6.1.0-26-amd64", "6.1.112-1", source: "linux"),
                              dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl").merge("available_version" => "3.0.15-1~deb12u1") ])
    kernel = row(server, cve: "CVE-2024-1", source_package: "linux", packages: [ "linux-image-6.1.0-25-amd64" ], installed: "6.1.106-3", fixed: "6.1.112-1", severity: "critical")

    plan = plans(server, [ kernel ]).sole
    assert_equal [ :reboot, [], true ], [ plan.state, plan.commands, plan.reboot ]
    assert plan.fixable?

    ssl = row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1", severity: "medium")
    fix = Vulnerabilities::FixCommands.new(server, [ kernel, ssl ])
    assert_equal [ :available, [ "apt-get install --only-upgrade libssl3" ] ], [ fix.system_plan.state, fix.system_plan.commands ], "the kernel is not reinstalled"
    assert_equal [ [ :reboot, "critical", "6.1.112-1", [], [ "CVE-2024-1" ] ], [ :packages, "medium", nil, [ "apt-get install --only-upgrade libssl3" ], [ "CVE-2024-9143" ] ] ],
                 fix.steps.map { [ it.kind, it.severity, it.name, it.commands, it.cves ] }
  end

  test "no fixed version: nothing to run" do
    server = servers(:web)
    vulnerability = row(server, cve: "CVE-2023-51767", source_package: "openssh", packages: [ "openssh-server" ], installed: "1:9.2p1-2+deb12u2", fixed: nil)

    plan = plans(server, [ vulnerability ]).sole
    assert_equal :none, plan.state
    assert_not plan.fixable?
    assert_empty plan.commands
  end

  test "an image: Compose services are pulled and recreated, other containers need the image pulled" do
    server = servers(:web)
    server.inventory_snapshots.create!(category: "services", status: "ok", collected_at: Time.current, checked_at: Time.current, data: { "containers" => [
      { "name" => "shop-web-1", "image" => "nginx:1.27", "working_dir" => "/srv/my shop", "project" => "shop", "service" => "web" },
      { "name" => "blog-web-1", "image" => "nginx:1.27", "working_dir" => "/srv/blog", "project" => "blog", "service" => "web" },
      { "name" => "proxy", "image" => "nginx:1.27" },
      { "name" => "cache", "image" => "redis:7" }
    ] })
    fixable = row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1",
                          origin: "image", image: "nginx:1.27")
    unfixed = row(server, cve: "CVE-2024-6119", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: nil,
                          origin: "image", image: "redis:7")

    nginx, redis = plans(server, [ fixable, unfixed ])
    assert_equal "nginx:1.27", nginx.image
    assert_equal :image, nginx.state
    assert_equal %w[blog-web-1 proxy shop-web-1], nginx.containers
    assert_equal [ "sudo docker pull nginx:1.27",
                   "cd /srv/blog && sudo docker compose pull web && sudo docker compose up -d web",
                   "cd /srv/my\\ shop && sudo docker compose pull web && sudo docker compose up -d web" ], nginx.commands
    assert_equal :none, redis.state
    assert_equal %w[cache], redis.containers
  end

  test "the system and each image get their own plan" do
    server = servers(:backup)
    host = row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1")
    image = row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1",
                        origin: "image", image: "nginx:1.27")

    assert_equal [ nil, "nginx:1.27" ], plans(server, [ image, host ]).map(&:image)
    assert_equal [ "docker pull nginx:1.27" ], plans(server, [ image ]).sole.commands
  end

  test "the whole server: one apt command for every fixable package, and steps most serious first" do
    server = servers(:web) # deploy
    record_packages(server, [ dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl").merge("available_version" => "3.0.15-1~deb12u1"),
                              dpkg("curl", "7.88.1-10+deb12u7").merge("available_version" => "7.88.1-10+deb12u8"),
                              dpkg("linux-image-6.1.0-25-amd64", "6.1.106-3", source: "linux").merge("available_version" => "6.1.112-1"),
                              dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh") ])
    row(server, cve: "CVE-2024-9143", source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1", severity: "medium")
    row(server, cve: "CVE-2024-2", source_package: "curl", packages: [ "curl" ], installed: "7.88.1-10+deb12u7", fixed: "7.88.1-10+deb12u8")
    row(server, cve: "CVE-2024-1", source_package: "linux", packages: [ "linux-image-6.1.0-25-amd64" ], installed: "6.1.106-3", fixed: "6.1.112-1", severity: "critical")
    row(server, cve: "CVE-2024-3", source_package: "linux", packages: [ "linux-image-6.1.0-25-amd64" ], installed: "6.1.106-3", fixed: "6.1.112-1", severity: "low")
    row(server, cve: "CVE-2023-51767", source_package: "openssh", packages: [ "openssh-server" ], installed: "1:9.2p1-2+deb12u2", fixed: nil)

    fix = Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities.fixable)
    assert_equal [ "sudo apt-get install --only-upgrade curl libssl3 linux-image-6.1.0-25-amd64" ], fix.system_plan.commands
    assert fix.system_plan.reboot

    steps = fix.steps
    assert_equal %w[critical high medium], steps.map(&:severity), "a package is updated once, at the severity of its most serious CVE"
    assert_equal [ [ "linux-image-6.1.0-25-amd64" ], [ "curl" ], [ "libssl3" ] ], steps.map(&:packages)
    assert_equal [ %w[CVE-2024-1 CVE-2024-3], %w[CVE-2024-2], %w[CVE-2024-9143] ], steps.map(&:cves)
    assert_equal [ true, false, false ], steps.map(&:reboot)
    assert_equal [ "sudo apt-get install --only-upgrade curl" ], steps.second.commands
  end

  test "the package lists are refreshed in the first step when a fix has not been seen yet" do
    server = servers(:backup) # root
    record_packages(server, [ dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"),
                              dpkg("curl", "7.88.1-10+deb12u7").merge("available_version" => "7.88.1-10+deb12u8") ])
    row(server, cve: "CVE-2024-6387", source_package: "openssh", packages: [ "openssh-server" ], installed: "1:9.2p1-2+deb12u2", fixed: "1:9.2p1-2+deb12u3", severity: "low")
    row(server, cve: "CVE-2024-2", source_package: "curl", packages: [ "curl" ], installed: "7.88.1-10+deb12u7", fixed: "7.88.1-10+deb12u8")

    first, second = Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities).steps
    assert_equal [ "apt-get update", "apt-get install --only-upgrade curl" ], first.commands
    assert_equal [ "apt-get install --only-upgrade openssh-server" ], second.commands
  end

  test "the images: one step per Compose project (its affected services only), one per image used without Compose" do
    server = servers(:web)
    server.inventory_snapshots.create!(category: "services", status: "ok", collected_at: Time.current, checked_at: Time.current, data: { "containers" => [
      { "name" => "shop-web-1", "image" => "nginx:1.27", "working_dir" => "/srv/my shop", "project" => "shop", "service" => "web" },
      { "name" => "shop-cache-1", "image" => "redis:7", "working_dir" => "/srv/my shop", "project" => "shop", "service" => "cache" },
      { "name" => "shop-db-1", "image" => "postgres:16", "working_dir" => "/srv/my shop", "project" => "shop", "service" => "db" },
      { "name" => "proxy", "image" => "nginx:1.27" }
    ] })
    { "nginx:1.27" => [ "CVE-2024-1", "medium", "3.0.15-1~deb12u1" ], "redis:7" => [ "CVE-2024-2", "critical", "3.0.15-1~deb12u1" ],
      "postgres:16" => [ "CVE-2024-3", "critical", nil ], "alpine:3" => [ "CVE-2024-4", "low", "3.0.15-1~deb12u1" ] }.each do |image, (cve, severity, fixed)|
      row(server, cve: cve, source_package: "openssl", packages: [ "libssl3" ], installed: "3.0.14-1~deb12u1", fixed: fixed, origin: "image", image: image, severity: severity)
    end

    compose, nginx, alpine = Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities.fixable).steps
    assert_equal [ :compose, "critical", "shop", "/srv/my shop" ], [ compose.kind, compose.severity, compose.name, compose.directory ]
    assert_equal [ "cd /srv/my\\ shop && sudo docker compose pull cache web && sudo docker compose up -d cache web" ], compose.commands
    assert_equal [ %w[nginx:1.27 redis:7], %w[shop-cache-1 shop-web-1], %w[CVE-2024-1 CVE-2024-2] ], [ compose.images, compose.containers, compose.cves ]
    assert_equal [ :image, "medium", [ "sudo docker pull nginx:1.27" ], [ "proxy" ] ], [ nginx.kind, nginx.severity, nginx.commands, nginx.containers ]
    assert_equal [ :image, "low", [] ], [ alpine.kind, alpine.severity, alpine.containers ], "an image without containers is pulled too"
  end
end
