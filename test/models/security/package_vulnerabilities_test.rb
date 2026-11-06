require "test_helper"

# The real case of DB-2: 2 900 kernel CVEs, fixed by 6.12.111 or 6.12.113,
# the repositories offering 6.12.113 through the linux-image-amd64 metapackage.
class PackageVulnerabilitiesTest < ActiveSupport::TestCase
  include PackageHelpers
  include VulnerabilityHelpers

  def row(cve, package: "linux", installed: "6.12.107-1", fixed: "6.12.113-1", severity: "high", packages: %w[linux-image-6.12.107+deb13-amd64 linux-libc-dev], image: nil)
    servers(:web).server_vulnerabilities.create!(origin: image ? "image" : "host", source: "debian", image: image, cve: cve, source_package: package, packages: packages,
                                                 installed_version: installed, fixed_version: fixed, severity: severity, distro_severity: severity)
  end

  setup do
    record_packages(servers(:web), [ dpkg("linux-image-6.12.107+deb13-amd64", "6.12.107-1", source: "linux-signed-amd64", source_version: "6.12.107+1"),
                                     dpkg("linux-image-amd64", "6.12.107-1", source: "linux-signed-amd64", source_version: "6.12.107+1").merge("available_version" => "6.12.113-1"),
                                     dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl").merge("available_version" => "3.0.14-1~deb12u2"),
                                     dpkg("curl", "7.88.1-10") ])
    row("CVE-2026-0001", fixed: "6.12.111-1", severity: "critical")
    row("CVE-2026-0002")
    row("CVE-2026-0003", fixed: nil, severity: "low")
    row("CVE-2024-9143", package: "openssl", installed: "3.0.14-1~deb12u1", fixed: "3.0.15-1~deb12u1", severity: "medium", packages: %w[libssl3])
    row("CVE-2023-1111", package: "curl", installed: "7.88.1-10", fixed: nil, packages: %w[curl])
    row("CVE-2024-9143", package: "openssl", installed: "3.0.11-1", fixed: "3.0.15-1~deb12u1", severity: "medium", packages: %w[libssl3], image: "nginx:1.27")
    CveScore.store("nvd", [ { cve: "CVE-2026-0001", score: 9.8 }, { cve: "CVE-2026-0002", score: 7.5 } ])
    CveRating.refresh!
  end

  def groups = PackageVulnerabilities.new(servers(:web).server_vulnerabilities, server: servers(:web)).groups.index_by(&:key)

  test "one line per package: the update that fixes every fixable CVE, how many it fixes, the worst" do
    linux = groups.fetch("linux")
    assert_equal [ 3, 2, 1, "6.12.107-1", "6.12.113-1", "critical", 9.8 ],
                 [ linux.count, linux.fixable_count, linux.unfixed_count, linux.installed_version, linux.target_version, linux.severity, linux.max_score.to_f ]
    assert_equal({ "critical" => 1, "high" => 1, "low" => 1 }, linux.by_severity)
    assert_equal %w[CVE-2026-0001 CVE-2026-0002 CVE-2026-0003], linux.ranked_rows.map(&:cve)
    assert linux.reboot?
  end

  test "whether the repositories offer it, and the apt command (the kernel through its metapackage)" do
    assert_equal [ :available, "apt-get install --only-upgrade linux-image-amd64" ], groups.fetch("linux").then { [ it.state, it.command ] }
    assert_equal [ :pending, "apt-get install --only-upgrade libssl3" ], groups.fetch("openssl").then { [ it.state, it.command ] },
                 "deb12u2 offered, the fix is 3.0.15: not yet in the repositories"
    assert_equal [ :none, nil ], groups.fetch("curl").then { [ it.state, it.command ] }
    assert_equal [ :image, nil, false ], groups.fetch("openssl@nginx:1.27").then { [ it.state, it.command, it.reboot? ] }
  end

  test "the most worth updating first" do
    assert_equal %w[linux openssl openssl@nginx:1.27 curl], groups.keys
  end

  test "the SQL of the worst severity follows the order of the severities" do
    assert_equal "ARRAY[#{Vulnerability::SEVERITIES.keys.map { |key| "'#{key}'" }.join(", ")}]", PackageVulnerabilities::SEVERITIES_SQL
    assert_equal 2, PackageVulnerabilities::WORST_SEVERITY.to_s.scan(PackageVulnerabilities::SEVERITIES_SQL).size
  end
end
