require "test_helper"

class Vulnerabilities::MatcherTest < ActiveSupport::TestCase
  include VulnerabilityHelpers
  include PackageHelpers

  setup do
    record_os(servers(:web))
    load_debian_feed
  end

  def packages(*list) = record_packages(servers(:web), list)

  test "a CVE affects the installed source version older than the fix, or without a fix yet" do
    packages(dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl"), dpkg("openssl", "3.0.14-1~deb12u1"),
             dpkg("openssh-server", "1:9.2p1-2+deb12u3", source: "openssh"), dpkg("libc6", "2.36-9+deb12u10+b1", source: "glibc", source_version: "2.36-9+deb12u10"),
             dpkg("nginx", "1.22.1-9"))

    rows = servers(:web).server_vulnerabilities.order(:cve).map { |row| row.attributes.slice("cve", "source_package", "packages", "installed_version", "fixed_version", "severity") }
    assert_equal [
      { "cve" => "CVE-2023-44487", "source_package" => "nginx", "packages" => [ "nginx" ], "installed_version" => "1.22.1-9", "fixed_version" => nil, "severity" => "unknown" },
      { "cve" => "CVE-2023-51767", "source_package" => "openssh", "packages" => [ "openssh-server" ], "installed_version" => "1:9.2p1-2+deb12u3", "fixed_version" => nil, "severity" => "low" },
      { "cve" => "CVE-2024-5535", "source_package" => "openssl", "packages" => %w[libssl3 openssl], "installed_version" => "3.0.14-1~deb12u1", "fixed_version" => "3.0.14-1~deb12u2", "severity" => "low" },
      { "cve" => "CVE-2024-9143", "source_package" => "openssl", "packages" => %w[libssl3 openssl], "installed_version" => "3.0.14-1~deb12u1", "fixed_version" => "3.0.15-1~deb12u1", "severity" => "low" }
    ], rows, "openssh fixed in the installed version, glibc fixed in its source version (binNMU +b1)"
    assert_equal [ "host", "debian" ], servers(:web).server_vulnerabilities.pick(:origin, :source)
    assert servers(:web).reload.vulnerabilities_checked_at
  end

  test "new serious fixable CVEs are logged, not on the first match, and become a critical health reason" do
    servers(:web).update_columns(vulnerabilities_checked_at: nil)
    assert_no_difference -> { Activity.of_kind(:vulnerability_found).count } do
      packages(dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"))
    end
    assert servers(:web).server_vulnerabilities.exists?(cve: "CVE-2024-6387")

    packages(dpkg("openssh-server", "1:9.2p1-2+deb12u3", source: "openssh"))
    packages(dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"))
    activity = Activity.of_kind(:vulnerability_found).sole
    assert_equal "1 vulnérabilité corrigeable sur « Web » : CVE-2024-6387 (openssh)", activity.summary

    packages(dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"))
    assert_equal 1, Activity.of_kind(:vulnerability_found).count, "already known"

    assert_equal [ "crit", "Vulnérabilité CVE-2024-6387 corrigeable" ], Inventory::HealthStatus.evaluate(servers(:web).reload).reasons.first.then { [ it.tone, it.text ] }
  end

  test "the alert severity of the settings decides what is serious" do
    packages(dpkg("openssl", "3.0.14-1~deb12u1"))
    assert_empty Inventory::HealthStatus.evaluate(servers(:web).reload).reasons.map(&:text).grep(/ulnérabilit/), "low and unknown only"

    AppSetting.current.update!(vulnerability_alert_severity: "medium")
    packages(dpkg("libc6", "2.36-9+deb12u9", source: "glibc"))
    assert_includes Inventory::HealthStatus.evaluate(servers(:web).reload).reasons.map(&:text), "Vulnérabilité CVE-2025-0395 corrigeable"

    AppSetting.current.update!(vulnerability_alert_severity: "none")
    assert_empty Inventory::HealthStatus.evaluate(servers(:web).reload).reasons.map(&:text).grep(/ulnérabilit/)

    AppSetting.current.update!(vulnerability_alert_severity: "any")
    packages(dpkg("nginx", "1.22.1-9"), dpkg("openssl", "3.0.14-1~deb12u1"))
    assert_includes Inventory::HealthStatus.evaluate(servers(:web).reload).reasons.map(&:text), "2 vulnérabilités graves corrigeables", "even the unrated ones; nginx has no fix"
  end

  test "the severity of the server's groups, and an exploited CVE whatever its severity" do
    packages(dpkg("openssl", "3.0.14-1~deb12u1"))
    AppSetting.current.update!(vulnerability_alert_severity: "medium")
    server_groups(:production).update!(vulnerability_alert_severity: "critical")
    packages(dpkg("libc6", "2.36-9+deb12u9", source: "glibc"))
    assert_empty Activity.of_kind(:vulnerability_found), "medium: below the group's severity"

    packages(dpkg("openssl", "3.0.14-1~deb12u1"))
    CveRating.create!(cve: "CVE-2025-0395", exploited: true)
    packages(dpkg("libc6", "2.36-9+deb12u9", source: "glibc"))
    assert_equal [ "CVE-2025-0395" ], Activity.of_kind(:vulnerability_found).sole.data["cves"], "exploited, although medium"
  end

  test "nothing without a feed or for another distribution" do
    record_os(servers(:db), id: "alpine", version_id: "3.20")
    record_packages(servers(:db), [ dpkg("openssl", "1.0") ])
    assert_empty servers(:db).server_vulnerabilities

    record_os(servers(:db), id: "ubuntu", codename: "noble", version_id: "24.04")
    record_packages(servers(:db), [ dpkg("openssl", "1.0") ])
    assert_nil servers(:db).reload.vulnerabilities_checked_at, "the Ubuntu feed was never loaded"
  end

  test "the kernel: signed images belong to linux, the running one counts (real DB-1 packages)" do
    Vulnerability.create!(source: "debian", release: "bookworm", package: "linux", cve: "CVE-2026-0001", fixed_version: "6.12.100-1", severity: "high")
    Vulnerability.create!(source: "debian", release: "bookworm", package: "linux", cve: "CVE-2026-0002", fixed_version: "6.12.110-1", severity: "high")
    servers(:web).inventory("os").update!(data: servers(:web).inventory("os").data.merge("kernel" => "6.12.107+deb13-amd64"))
    packages(dpkg("linux-image-6.12.107+deb13-amd64", "6.12.107-1", source: "linux-signed-amd64", source_version: "6.12.107+1"),
             dpkg("linux-image-6.12.94+deb13-amd64", "6.12.94-1", source: "linux-signed-amd64", source_version: "6.12.94+1"),
             dpkg("linux-image-amd64", "6.12.107-1", source: "linux-signed-amd64", source_version: "6.12.107+1"),
             dpkg("linux-libc-dev", "6.12.113-1", source: "linux"))

    rows = servers(:web).server_vulnerabilities.where(source_package: "linux")
    assert_equal [ [ "CVE-2026-0002", "6.12.107-1" ] ], rows.pluck(:cve, :installed_version), "the running 6.12.107, not the old 6.12.94 nor the headers"
    assert_equal %w[linux-image-6.12.107+deb13-amd64 linux-libc-dev], rows.sole.packages
  end

  test "during a collection, the CVEs follow the kernel just collected, not the one loaded before (real DB-3 case)" do
    Vulnerability.create!(source: "debian", release: "bookworm", package: "linux", cve: "CVE-2026-0002", fixed_version: "6.12.113-1", severity: "high")
    server = Server.includes(:inventory_snapshots).find(servers(:web).id)
    server.inventory("os").update_columns(data: server.inventory("os").data.merge("kernel" => "6.12.107+deb13-amd64"))
    server.inventory_snapshots.reset
    server.inventory("os") # loaded with the old kernel, as at the start of a collection
    Inventory::Snapshot.where(server_id: server.id, category: "os").update_all(data: server.inventory("os").data.merge("kernel" => "6.12.113+deb13-amd64"))
    record_packages(server, [ dpkg("linux-image-6.12.107+deb13-amd64", "6.12.107-1", source: "linux-signed-amd64"),
                              dpkg("linux-image-6.12.113+deb13-amd64", "6.12.113-1", source: "linux-signed-amd64") ])

    assert_empty server.server_vulnerabilities.where(source_package: "linux"), "rebooted on 6.12.113: fixed"
  end
end
