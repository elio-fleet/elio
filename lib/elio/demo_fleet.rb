# A fictitious fleet (TEST-NET addresses 198.51.100.x, command outputs
# recorded in test/fixtures/files/inventory) for the README screenshots
# (test/screenshots/readme_screenshots.rb), the before / after screenshots of
# pull requests and a demo database (bin/rails dev:demo). Never the network.
module Elio
  class DemoFleet
    FIX = Rails.root.join("test/fixtures/files/inventory")
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

    # Servers, groups, inventories, packages, vulnerabilities and scores.
    # Returns { web:, db:, backup: }.
    def build_core
      Server.delete_all
      production = ServerGroup.find_or_create_by!(name: "Production") { |group| group.color = "red" }.tap { |group| group.update!(expected_ports: "22, 80, 443, 6432") }
      infra = ServerGroup.find_or_create_by!(name: "Infra") { |group| group.color = "emerald" }
      staging = ServerGroup.find_or_create_by!(name: "Staging") { |group| group.color = "sky" }

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
      network = Inventory::Collectors::Network.parse(sections(FIX.join("network/debian13-wireguard.txt")))
      snapshot(db, "network", network)
      db.update_columns(Inventory::Collectors::Network.server_attributes(network))
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
      { web: web, db: db, backup: backup }
    end

    # The DNS of the fleet (Technitium, Gandi), the SSH sources, an IPv6
    # address and the prompt instructions.
    def build_dns_and_firewall(db)
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
      ServerGroup.find_by!(name: "Production").update!(ssh_source_ids: [ elio_source.id ])
      db.update!(extra_addresses_text: "2001:db8:20::20")
      AppSetting.current.update!(prompt_instructions: { "firewall" => "For the SSH port, always put the rules last." })
    end

    def build_notes(db, admin:, operator:)
      db.notes.create!(user: operator, created_at: 3.days.ago, updated_at: 3.days.ago, body: <<~MD)
        ## Role
        Main **PostgreSQL 16** of the shop, replicated to `backup` every night.

        - Restart: `systemctl restart postgresql@16-main`
        - Maintenance window: Sunday 02:00–04:00

        Runbook: https://wiki.example.internal/db-prod
      MD
      db.notes.create!(user: admin, body: "> Incident 2026-11-03: disk full (WAL). `wal_keep_size` lowered to 2 GB.")
    end

    # The extensions without their services (dev:demo): what their syncs
    # would have stored.
    def build_extensions_offline(web, db)
      { "uptime_kuma" => { "url" => "https://uptime.example.internal" }, "ovh" => { "endpoint" => "ovh-eu" } }.each do |kind, settings|
        Integration.find_or_initialize_by(kind: kind).tap { |integration| integration.settings = settings; integration.save!(validate: false) }
                   .update_columns(enabled: true, last_synced_at: 15.minutes.ago)
      end
      [ [ "1", "[SRV] db-prod", "198.51.100.20", db, 1 ], [ "2", "[SRV] web-prod-1", "198.51.100.10", web, 1 ], [ "4", "[SRV] staging", "198.51.100.77", nil, 0 ],
        [ "6", "Old VPN gateway", "192.0.2.44", nil, 0 ] ].each do |id, name, host, server, status|
        UptimeKumaMonitor.create!(monitor_id: id, name: name, monitor_type: "ping", hostname: host, status: status, server: server, matched_by: (server && "ip"),
                                  uptime: { "1d" => (status == 1 ? 0.9995 : 0.91), "30d" => (status == 1 ? 0.9991 : 0.95) })
      end
      OvhResource.create!(kind: "ip", external_id: "198.51.100.20/32", name: "198.51.100.20/32", server: db,
                          data: { "firewall" => { "198.51.100.20" => { "enabled" => true, "rules" => [
                            { "sequence" => 0, "action" => "permit", "protocol" => "tcp", "destinationPort" => "eq 22", "source" => "192.0.2.0/24" },
                            { "sequence" => 1, "action" => "permit", "protocol" => "tcp", "destinationPort" => "eq 443" },
                            { "sequence" => 19, "action" => "deny", "protocol" => "ipv4" } ] } },
                                  "mitigation" => { "198.51.100.20" => { "permanent" => false, "state" => "ok" } }, "reverse" => { "198.51.100.20" => "db-prod.example.internal" } })
    end
  end
end
