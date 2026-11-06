require "test_helper"

class Vulnerabilities::FeedsTest < ActiveSupport::TestCase
  include VulnerabilityHelpers

  def debian_rows(releases)
    [].tap { |rows| File.open(debian_tracker_path, "rb") { |io| Vulnerabilities::DebianTracker.each_row(io, releases: releases) { |row| rows << row } } }
  end

  test "Debian: CVEs of the releases asked for, with their fix and urgency" do
    rows = debian_rows(%w[bookworm]).index_by { |row| [ row[:package], row[:cve] ] }

    assert_equal [ %w[glibc CVE-2025-0395], %w[nginx CVE-2023-44487], %w[openssh CVE-2023-51767], %w[openssh CVE-2024-6387],
                   %w[openssl CVE-2024-5535], %w[openssl CVE-2024-9143] ], rows.keys.sort
    assert_equal({ release: "bookworm", package: "openssh", cve: "CVE-2024-6387", fixed_version: "1:9.2p1-2+deb12u3", severity: "high", primary: true },
                 rows[%w[openssh CVE-2024-6387]].except(:description))
    assert_match "« regreSSHion »", rows[%w[openssh CVE-2024-6387]][:description]
    assert_equal [ nil, "low" ], rows[%w[openssh CVE-2023-51767]].values_at(:fixed_version, :severity), "open: no fix yet"
    assert_equal "unknown", rows[%w[nginx CVE-2023-44487]][:severity], "not yet assigned"
    assert_equal "low", rows[%w[openssl CVE-2024-5535]][:severity], "not yet assigned, but no advisory planned (nodsa)"
    assert_equal [ "bookworm", "trixie" ], debian_rows(%w[bookworm trixie]).map { |row| row[:release] }.uniq.sort
    assert_empty debian_rows(%w[bullseye]), "fixed in version 0 = not affected"
  end

  test "Debian: another file is refused" do
    assert_raises(Vulnerabilities::Error) { Vulnerabilities::DebianTracker.each_row(StringIO.new(%({"openssl": [1]})), releases: %w[bookworm]) { } }
    assert_raises(Vulnerabilities::Error) { Vulnerabilities::DebianTracker.each_row(StringIO.new("not json"), releases: %w[bookworm]) { } }
  end

  test "Ubuntu OSV: per release, Pro / FIPS and negligible issues skipped, USN rows not primary" do
    rows = []
    Vulnerabilities::UbuntuOsv.each_row(ubuntu_osv_zip, releases: %w[24.04]) { |row| rows << row }

    assert_equal [ [ "krb5", "CVE-2024-26461", nil, "medium", true ], [ "openssh", "CVE-2024-6387", "1:9.6p1-3ubuntu13.3", "high", true ],
                   [ "openssh", "CVE-2024-6387", "1:9.6p1-3ubuntu13.3", "unknown", false ] ],
                 rows.map { |row| row.values_at(:package, :cve, :fixed_version, :severity, :primary) }.sort_by { |row| [ row[0], row[4] ? 0 : 1 ] }
    rows = []
    Vulnerabilities::UbuntuOsv.each_row(ubuntu_osv_zip, releases: %w[22.04]) { |row| rows << row }
    assert_equal [ "1:8.9p1-3ubuntu0.10" ], rows.map { |row| row[:fixed_version] }.uniq
  end

  test "Ubuntu OSV: one archive per release, LTS or not; an archive is about the releases of every record" do
    assert_equal "https://osv-vulnerabilities.storage.googleapis.com/Ubuntu%3A24.04%3ALTS/all.zip", Vulnerabilities::UbuntuOsv.url("24.04")
    assert_equal "Ubuntu:24.10", Vulnerabilities::UbuntuOsv.ecosystem("24.10")
    assert_equal "Ubuntu:22.04:LTS", Vulnerabilities::UbuntuOsv.ecosystem("22.04")
    assert_equal %w[24.04], Vulnerabilities::UbuntuOsv.archive_releases(ubuntu_osv_zip)
  end

  test "Ubuntu OSV: a broken archive is refused" do
    Dir.mktmpdir do |dir| # its own folder: tmp/test may not exist yet, depending on the order of the tests
      path = File.join(dir, "broken.zip")
      File.write(path, "PK not a zip")
      assert_raises(Vulnerabilities::Error) { Vulnerabilities::UbuntuOsv.each_row(path, releases: %w[24.04]) { } }
    end
  end

  test "the kind of an imported file is recognized from its content" do
    assert_equal "debian", Vulnerabilities::Update.detect(debian_tracker_path)
    assert_equal "ubuntu", Vulnerabilities::Update.detect(ubuntu_osv_zip)
    assert_nil Vulnerabilities::Update.detect(file_fixture("inventory/scheduled_tasks/none.txt").to_s)
  end
end
