require "application_system_test_case"

# Screenshots of the README and of the website (docs/screenshots/<language>), on a
# fictitious fleet (TEST-NET addresses 198.51.100.x, recorded command
# outputs of test/fixtures). Not part of the test suite (no _test suffix):
#
#   bin/rails tailwindcss:build
#   bin/rails test test/screenshots/readme_screenshots.rb
#
# Then optimize them: script/optimize-screenshots.
class ReadmeScreenshots < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include PackageHelpers
  include UptimeKumaHelpers
  include OvhHelpers

  FIX = Rails.root.join("test/fixtures/files/inventory")
  OUT = Rails.root.join("docs/screenshots")
  AGO = 9.minutes

  def sections(path) = Inventory::Collector.sections(File.read(path))

  def snapshot(server, category, data, status: "ok")
    server.inventory_snapshots.create!(category: category, status: status, data: data, collected_at: AGO.ago, checked_at: AGO.ago, privileged: true)
  end

  def seed(name, host, user, os_file, groups:, health: {}, reachable: true)
    server = Server.create!(name: name, host: host, port: 22, username: user, reachable: reachable, ssh_ok: true, ssh_checked_at: Time.current,
                            last_checked_at: Time.current, privilege: "sudo", inventoried_at: AGO.ago)
    server.server_groups = groups
    os = Inventory::Collectors::Os.parse(File.read(FIX.join("os/#{os_file}.txt"))).merge("hostname" => "#{name}.example.internal")
    data = Inventory::Collectors::Health.parse(File.read(FIX.join("health/#{os_file == "ubuntu2204" ? "ubuntu2404" : os_file}.txt"))).merge(health)
    snapshot(server, "os", os)
    snapshot(server, "health", data)
    server.update_columns(os_name: os["name"], os_id: os["id"], os_version: os["version_id"])
    48.times do |i|
      server.health_samples.create!(collected_at: (i * 30).minutes.ago, load_percent: (data["load_percent"].to_f + 12 * Math.sin(i / 3.0 + name.size)).clamp(1, 99),
                                    memory_percent: data.dig("memory", "used_percent").to_f - i * 0.05, disk_percent: data["disk_max_percent"].to_f - i * 0.15)
    end
    server
  end

  def disk(mount, percent, size) = { "disks" => [ { "mount" => mount, "used_percent" => percent, "size" => size, "used" => size * percent / 100, "type" => "ext4" } ], "disk_max_percent" => percent }

  DESCRIPTIONS = {
    "CVE-2024-6387" => "A signal handler race condition was found in OpenSSH's server (sshd): an unauthenticated remote attacker may be able to run code as root (regreSSHion).",
    "CVE-2024-45491" => "An integer overflow in libexpat's dtdCopy on 32-bit platforms (nodeCount)."
  }.freeze

  # CVEs of a package on a server, with scores from three providers.
  def vulnerabilities(server, package, binaries, installed, fixed, cves, image: nil)
    cves.each_with_index do |(cve, severity, score, fix), index|
      server.server_vulnerabilities.create!(origin: image ? "image" : "host", source: "debian", image: image, cve: cve, source_package: package, packages: binaries,
                                            installed_version: installed, fixed_version: fix == :none ? nil : (fix || fixed), severity: severity, distro_severity: index.even? ? "unknown" : severity)
      next unless score

      CveScore.store("nvd", [ { cve: cve, score: score, version: "3.1", vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", data: { "description" => DESCRIPTIONS.fetch(cve, "A vulnerability in #{package} (#{cve}).") } } ])
      CveScore.store("cveorg", [ { cve: cve, score: score, version: "3.1", vector: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", severity: "high", data: { "from" => "CNA" } } ])
      CveScore.store("redhat", [ { cve: cve, score: (score - 0.4).round(1).clamp(0, 10), version: "3", vector: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H" } ])
      CveScore.store("epss", [ { cve: cve, score: index.zero? ? 0.42 : 0.004, data: { "percentile" => index.zero? ? 0.97 : 0.3 } } ])
    end
  end

  def kernel_cves(count)
    Array.new(count) do |i|
      severity = %w[critical high high medium medium medium low unknown unknown unknown][i % 10]
      [ "CVE-2025-#{38_000 + i}", severity, ({ "critical" => 9.8, "high" => 7.8, "medium" => 5.5, "low" => 3.3 }[severity]), (i % 4 == 3 ? :none : nil) ]
    end
  end

  test "README and website screenshots" do
    stub_method_until_teardown(Servers::Ping, :reachable?, ->(host, *, **) { !host.end_with?(".77") })
    stub_method_until_teardown(Ssh::Check, :call, ->(*, **) { Ssh::Check::Result.new(success: true, message: "Connexion SSH réussie", details: "ok") })
    keys = [ public_keys(:alice).content, public_keys(:ci).content, ssh_keys(:main).public_key, Ssh::KeyGenerator.generate(comment: "jdupont@old-laptop").public_key ]
    # Elio logs in as root on "backup": the keys of its other accounts are read too.
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all, keys_read(lambda { |*, **|
      Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(keys.join("\n")), error_title: nil, error_details: nil)
    }, others: { "backup" => [ public_keys(:ci).content ] }))
    Server.delete_all
    production = server_groups(:production).tap { |group| group.update!(expected_ports: "22, 80, 443, 6432") }
    infra = ServerGroup.create!(name: "Infra", color: "emerald")
    staging = server_groups(:staging)

    web = seed("web-prod-1", "198.51.100.10", "deploy", "ubuntu2404", groups: [ production ],
               health: { "reboot_required" => false, "ntp_synchronized" => true, "updates" => { "total" => 3, "security" => 0 } })
    seed("web-prod-2", "198.51.100.11", "deploy", "ubuntu2404", groups: [ production ],
         health: { "reboot_required" => false, "ntp_synchronized" => true, "updates" => { "total" => 3, "security" => 0 } }.merge(disk("/", 52.0, 50.gigabytes)))
    db = seed("db-prod", "198.51.100.20", "admin", "debian12", groups: [ production ])
    seed("worker-1", "198.51.100.30", "deploy", "ubuntu2204", groups: [ production ], health: { "ntp_synchronized" => true }.merge(disk("/", 61.0, 80.gigabytes)))
    backup = seed("backup", "198.51.100.40", "root", "debian12", groups: [ infra ], health: { "failed_units" => [] }.merge(disk("/srv/backup", 83.0, 2.terabytes)))
    seed("monitoring", "198.51.100.50", "root", "debian12", groups: [ infra ],
         health: { "failed_units" => [], "updates" => { "total" => 2, "security" => 0 } }.merge(disk("/", 38.0, 100.gigabytes)))
    seed("staging", "198.51.100.77", "deploy", "ubuntu2404", groups: [ staging ], reachable: false)

    # db-prod: everything the server page shows.
    snapshot(db, "ports", Inventory::Collectors::Ports.parse(sections(FIX.join("ports/debian12.txt"))))
    services = File.read(FIX.join("services/debian12.txt"))
    units = Inventory::Collectors::Services.parse_units(services.split("@@elio unit-files").first.sub("@@elio units\n", ""),
                                                        Inventory::Collectors::Services.parse_unit_files(services.split("@@elio unit-files\n").last.split("@@elio docker").first))
    snapshot(db, "services", { "units" => units, "containers" => Inventory::Collectors::Services.parse_containers(File.read(FIX.join("services/docker_ps.txt"))), "docker" => "ok" })
    snapshot(db, "scheduled_tasks", Inventory::Collectors::ScheduledTasks.parse(File.read(FIX.join("scheduled_tasks/debian13.txt")), now: Time.zone.at(1_762_000_000)))
    docker = Inventory::Collectors::Docker.parse(sections(FIX.join("docker/debian13.txt")))
    docker["images"].each { |image| image["reference"] = image["tags"].first || image["id"] }
    snapshot(db, "docker", docker.merge("docker" => "ok", "version" => "27.3.1", "scans" => { "sha256:#{"a" * 64}" => { "method" => "elio", "at" => AGO.ago.iso8601, "count" => 12 } }))
    ImageUpdate.create!(reference: "nginx:1.27", registry: "docker.io", repository: "library/nginx", tag: "1.27", remote_digest: "sha256:#{"9" * 64}", checked_at: AGO.ago)
    packages = Inventory::Collectors::Packages
    debian = File.read(FIX.join("packages/debian12.txt"))
    data = packages.summarize(packages.parse_dpkg(debian.split("@@elio upgradable").first.sub("@@elio dpkg\n", ""), packages.parse_upgradable(debian)) +
                              packages.parse_docker(File.read(FIX.join("packages/docker_images.txt"))))
    snapshot(db, "packages", packages.snapshot_data(data))
    packages.record(db, data, Time.current)

    # Vulnerabilities: the kernel (the bulk of them), openssh, an image.
    [ db, web ].each do |server|
      vulnerabilities(server, "linux", %w[linux-image-6.1.0-25-amd64 linux-libc-dev], "6.1.106-3", "6.1.119-1", kernel_cves(server == db ? 64 : 40))
      vulnerabilities(server, "openssh", %w[openssh-client openssh-server], "1:9.2p1-2+deb12u2", "1:9.2p1-2+deb12u3",
                      [ [ "CVE-2024-6387", "high", 8.1 ], [ "CVE-2023-51767", "low", 7.0, :none ] ])
    end
    vulnerabilities(db, "openssl", %w[libssl3], "3.0.14-1~deb12u1", "3.0.15-1~deb12u1", [ [ "CVE-2024-9143", "medium", 4.3 ], [ "CVE-2024-5535", "low", 9.1 ] ])
    vulnerabilities(db, "expat", %w[libexpat1], "2.5.0-1", "2.5.0-1+deb12u1", [ [ "CVE-2024-45491", "critical", 9.8 ], [ "CVE-2024-45492", "critical", 9.8 ] ], image: "nginx:1.27")
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
    db.packages.where(name: "openssh-server").update_all(source_name: "openssh", available_version: "1:9.2p1-2+deb12u3")
    Inventory::Package.create!(server: db, manager: "dpkg", name: "linux-image-amd64", version: "6.1.106-3", source_name: "linux", source_version: "6.1.106-3", available_version: "6.1.119-1")
    VulnerabilityFeed.for("debian").update!(refreshed_at: 2.hours.ago, origin: "download", entries_count: 56_329, releases: %w[bookworm])
    CveRating.refresh!
    ScoreProvider.all_providers.each { |provider| provider.update!(last_run_at: 3.hours.ago) }

    # Extensions, synchronized for real against fake services (as in the tests).
    enable_uptime_kuma
    uptime_kuma_metrics(metrics_page(
      { id: 1, name: "[SRV] db-prod", hostname: "198.51.100.20", status: 1, uptime: 0.9998 },
      { id: 2, name: "[SRV] web-prod-1", hostname: "198.51.100.10", status: 1, uptime: 0.9991 },
      { id: 3, name: "shop.example.com", type: "http", url: "https://shop.example.com", hostname: "null", status: 1, cert_days: 23, uptime: 0.9995 },
      { id: 4, name: "[SRV] staging", hostname: "198.51.100.77", status: 0, uptime: 0.912 },
      { id: 5, name: "[SRV] db-prod PostgreSQL", type: "port", hostname: "198.51.100.20", status: 1, uptime: 1.0 },
      { id: 6, name: "Old VPN gateway", hostname: "192.0.2.44", status: 0, uptime: 0.0 }
    ))
    Integration.find_by!(kind: "uptime_kuma").sync!
    UptimeKumaMonitor.find_by!(monitor_id: "3").update!(server: web, matched_by: "manual")
    enable_ovh
    fake_ovh(JSON.parse(ovh_account(expiration: 12.days.from_now.to_date).to_json
                          .gsub("198.51.100.20", "198.51.100.11").gsub("203.0.113.10", "198.51.100.20").gsub("web.example.com.", "db-prod.example.internal.")
                          .gsub("198.51.100.7", "198.51.100.40")))
    Integration.find_by!(kind: "ovh").sync!
    # Technitium (internal zone) next to OVH's public one: the DNS of the fleet, a name that differs by source.
    Integration.find_or_initialize_by(kind: "technitium").update!(enabled: true, settings: { "url" => "https://dns.example.internal:53443" }, secrets: { "api_token" => "t" },
                                                                  last_synced_at: 20.minutes.ago)
    Dns::Store.replace("technitium", [
      { zone: "lan.example.internal", name: "db.lan.example.internal", record_type: "A", value: "198.51.100.20" },
      { zone: "lan.example.internal", name: "pg.lan.example.internal", record_type: "CNAME", value: "db.lan.example.internal" },
      { zone: "lan.example.internal", name: "backup.lan.example.internal", record_type: "A", value: "198.51.100.40" },
      { zone: "lan.example.internal", name: "old-vpn.lan.example.internal", record_type: "A", value: "192.0.2.44" }
    ])
    # Gandi (public domain) as a third DNS source, with its domains.
    Integration.find_or_initialize_by(kind: "gandi").update!(enabled: true, secrets: { "api_token" => "pat" }, last_synced_at: 12.minutes.ago,
                                                             settings: { "alert_expiring" => true },
                                                             state: { "domains" => [ { "fqdn" => "example.org", "expires_at" => 18.days.from_now.iso8601, "autorenew" => false, "livedns" => true },
                                                                                     { "fqdn" => "shop.example", "expires_at" => 240.days.from_now.iso8601, "autorenew" => true, "livedns" => true } ] })
    Dns::Store.replace("gandi", [
      { zone: "example.org", name: "example.org", record_type: "A", value: "198.51.100.10" },
      { zone: "example.org", name: "www.example.org", record_type: "CNAME", value: "example.org" },
      { zone: "shop.example", name: "shop.example", record_type: "A", value: "198.51.100.20" }
    ])
    # Firewall: SSH only from Elio and the office (the Production group), an IPv6 not covered by the OVH firewall.
    elio_source = SshSource.create!(name: "Elio", cidr: "198.51.100.250", position: 0)
    SshSource.create!(name: "Office", cidr: "192.0.2.0/24", position: 1)
    server_groups(:production).update!(ssh_source_ids: [ elio_source.id ])
    db.update!(extra_addresses_text: "2001:db8:20::20")
    AppSetting.current.update!(prompt_instructions: { "firewall" => "For the SSH port, always put the rules last." })

    db.notes.create!(user: users(:operator), created_at: 3.days.ago, updated_at: 3.days.ago, body: <<~MD)
      ## Role
      Main **PostgreSQL 16** of the shop, replicated to `backup` every night.

      - Restart: `systemctl restart postgresql@16-main`
      - Maintenance window: Sunday 02:00–04:00

      Runbook: https://wiki.example.internal/db-prod
    MD
    db.notes.create!(user: users(:one), body: "> Incident 2026-11-03: disk full (WAL). `wal_keep_size` lowered to 2 GB.")

    Server.find_each(&:refresh_health!)
    Activity.record!(:vulnerability_found, server: db, user: nil, count: 2, cves: %w[CVE-2024-45491 CVE-2024-45492], packages: %w[expat], image: "nginx:1.27")
    Activity.record!(:port_opened, server: db, user: nil, port: "6432/tcp", process: "docker-proxy")
    Activity.record!(:key_added, server: web, public_key: public_keys(:alice), unix_user: "deploy", user: users(:one), duration_label: "4 h")
    AccountSnapshot.record!(backup, AuthorizedKeysAccount.login(backup), AuthorizedKey.parse(keys.join("\n")))
    Automation.all_kinds.each do |automation|
      automation.update!(enabled: automation.inventory? || automation.kind.in?(%w[servers_ping vulnerabilities_update cve_scores_update docker_image_updates]),
                         last_run_at: 7.minutes.ago)
    end

    # One set per language (docs/screenshots/<language>/), the user's
    # language deciding over the browser's.
    access = Activity.of_kind(:key_added).last
    %w[en fr].each do |locale|
      I18n.with_locale(locale) do
        Automation.update_all(last_result: I18n.t("automation.results.inventoried", done: 7, count: 7))
        access.update!(data: access.data.merge("duration_label" => TemporaryAccess.label_for(4.hours)))
      end
      users(:one).update!(locale: locale)
      sign_in users(:one)
      @out = OUT.join(locale)
      FileUtils.mkdir_p(@out)
      shoot = lambda do |name, path, theme: "light", &before|
        visit root_path
        page.execute_script("localStorage.setItem('elio-theme', '#{theme}')")
        visit path
        before&.call
        sleep 1.2
        # As tall as the content (720 to 1400 px), not a fixed square with empty
        # space below: the bottom of the last element of <main>, plus the window
        # chrome (resize_to sets the outer size).
        content = evaluate_script(<<~JS).to_i
          Math.ceil(Math.max(...Array.from(document.querySelectorAll("main *")).map((e) => e.getBoundingClientRect().bottom + window.scrollY)) + 32)
        JS
        chrome = evaluate_script("window.outerHeight - window.innerHeight").to_i
        page.driver.browser.manage.window.resize_to(1400, content.clamp(720, 1400) + chrome)
        sleep 0.3
        page.save_screenshot(@out.join("#{name}.png").to_s)
        page.driver.browser.manage.window.resize_to(1400, 1400)
      end

      shoot.("overview", root_path)
      shoot.("fleet", servers_path(view: "list"))
      shoot.("fleet-grid", servers_path(view: "grid"))
      shoot.("fleet-dark", servers_path(view: "list"), theme: "dark")
      shoot.("server", server_path(db))
      shoot.("server-dark", server_path(db), theme: "dark")
      shoot.("vulnerabilities-by-package", server_path(db, tab: "vulnerabilities", view: "packages")) do
        find("li.vulnerability-package[data-package=linux] summary").click
      end
      shoot.("vulnerability-detail", server_path(db, tab: "vulnerabilities", view: "cves")) do
        find("tr.server-vulnerability[data-cve='CVE-2024-6387']").click
        assert_selector "dialog.vulnerability-dialog[open] .vulnerability-detail"
      end
      shoot.("fleet-vulnerabilities", vulnerabilities_path(view: "packages"))
      shoot.("docker", server_path(db, tab: "docker"))
      shoot.("scheduled-tasks", server_path(db, tab: "schedules"))
      shoot.("ports", server_path(db, tab: "ports"))
      shoot.("firewall", server_path(db, tab: "firewall"))
      shoot.("firewall-settings", settings_firewall_path)
      shoot.("gandi", edit_settings_integration_path("gandi"))
      shoot.("ssh-keys", server_path(backup, tab: "keys"))
      shoot.("packages", packages_path(q: "ssl"))
      shoot.("score-providers", settings_vulnerabilities_path) { find("#score-providers").scroll_to(:top) }
      shoot.("automations", settings_automations_path)
      shoot.("uptime-kuma-monitors", monitors_path)
      shoot.("ovh", server_path(db, tab: "ovh"))
      shoot.("dns", dns_records_path)
      shoot.("notes", server_path(db, tab: "notes"))
      shoot.("docker-cves", docker_path(tab: "cves")) { first("section.image-vulnerabilities details summary").click }
      shoot.("keyring-outside", public_keys_path(kind: "outside"))
    end
  end
end
