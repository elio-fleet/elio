require "test_helper"

class Vulnerabilities::UpdateTest < ActiveSupport::TestCase
  include VulnerabilityHelpers
  include PackageHelpers
  include StubHelpers

  test "keeps the releases of the fleet only, remembers the feed, matches the servers" do
    record_os(servers(:web))
    record_packages(servers(:web), [ dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh") ])

    assert_equal "Debian Security Tracker : 6 vulnérabilités (bookworm)", load_debian_feed

    assert_equal %w[bookworm], Vulnerability.distinct.pluck(:release)
    feed = VulnerabilityFeed.for("debian")
    assert_equal [ 6, %w[bookworm], "import" ], [ feed.entries_count, feed.releases, feed.origin ]
    assert_equal %w[CVE-2023-51767 CVE-2024-6387], servers(:web).server_vulnerabilities.order(:cve).pluck(:cve)
  end

  test "a new import replaces the previous entries" do
    record_os(servers(:web))
    Vulnerability.create!(source: "debian", release: "bookworm", package: "old", cve: "CVE-1999-0001", severity: "low")
    load_debian_feed
    assert_not Vulnerability.exists?(cve: "CVE-1999-0001")
  end

  test "Ubuntu: a USN never replaces the UBUNTU-CVE record of the same CVE" do
    record_os(servers(:web), id: "ubuntu", codename: "noble", version_id: "24.04")
    Vulnerabilities::Update.call("ubuntu", path: ubuntu_osv_zip)

    assert_equal [ [ "krb5", "CVE-2024-26461", "medium" ], [ "openssh", "CVE-2024-6387", "high" ] ],
                 Vulnerability.where(source: "ubuntu").order(:package).pluck(:package, :cve, :severity)
  end

  test "Ubuntu: one download per release; the archive of a release does not empty the others" do
    record_os(servers(:web), id: "ubuntu", codename: "noble", version_id: "24.04")
    record_os(servers(:db), id: "ubuntu", codename: "jammy", version_id: "22.04")
    urls = []
    stub_method(Vulnerabilities::Download, :open, ->(url, **, &block) { urls << url; block.call(ubuntu_osv_zip) }) do
      Vulnerabilities::Update.call("ubuntu")
    end
    assert_equal [ Vulnerabilities::UbuntuOsv.url("22.04"), Vulnerabilities::UbuntuOsv.url("24.04") ], urls
    assert_equal({ "22.04" => 1, "24.04" => 2 }, Vulnerability.where(source: "ubuntu").group(:release).count)

    Vulnerability.where(release: "22.04").update_all(description: "kept")
    Vulnerabilities::Update.call("ubuntu", path: ubuntu_osv_zip)
    assert_equal [ "kept" ], Vulnerability.where(release: "22.04").pluck(:description), "a 24.04 archive only replaces 24.04"
    assert_equal %w[22.04 24.04], VulnerabilityFeed.for("ubuntu").releases
  end

  test "a file without any release of the fleet is refused and changes nothing" do
    record_os(servers(:web), codename: "bullseye", version_id: "11")
    error = assert_raises(Vulnerabilities::Error) { load_debian_feed }
    assert_match "Aucune vulnérabilité des versions du parc (bullseye)", error.message
  end

  test "nothing to download without servers of that distribution" do
    assert_equal "Debian Security Tracker : aucun serveur concerné", Vulnerabilities::Update.call("debian")
  end

  test "downloads the feed and remembers a failure" do
    record_os(servers(:web))
    stub_method(Vulnerabilities::Download, :open, ->(url, **, &block) { assert_equal Vulnerabilities::DebianTracker::URL, url; block.call(debian_tracker_path) }) do
      Vulnerabilities::Update.call("debian")
    end
    assert_equal "download", VulnerabilityFeed.for("debian").origin

    stub_method(Vulnerabilities::Download, :open, ->(*, **) { raise Vulnerabilities::Error, "HTTP 503" }) do
      assert_raises(Vulnerabilities::Error) { Vulnerabilities::Update.call("debian") }
    end
    feed = VulnerabilityFeed.for("debian")
    assert feed.failed?
    assert_equal [ "HTTP 503", 6 ], [ feed.last_error, Vulnerability.count ], "the previous entries stay"
  end

  test "the releases come from the os inventories" do
    record_os(servers(:web))
    record_os(servers(:db), id: "ubuntu", codename: "noble", version_id: "24.04")
    assert_equal({ "debian" => %w[bookworm], "ubuntu" => %w[24.04] }, Vulnerabilities.releases)
    assert_equal [ "debian", "trixie" ], Vulnerabilities.target({ "id" => "raspbian", "codename" => "trixie" })
    assert_nil Vulnerabilities.target({ "id" => "alpine", "version_id" => "3.20" })
  end
  test "remembers the releases the feed does not hold, and scans again the images that waited for a new release" do
    record_os(servers(:web), codename: "bookworm")
    db = servers(:db)
    record_os(db, codename: "jessie")
    db.inventory_snapshots.create!(category: "docker", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                   data: { "images" => [], "scans" => { "sha256:1" => { "method" => "elio", "os" => { "id" => "debian", "codename" => "bookworm" }, "error" => "bookworm not yet in the feed" } } })

    rescanned = []
    stub_method(Inventory::CollectJob, :perform_later, ->(server, categories) { rescanned << [ server, categories ] }) { load_debian_feed }

    assert_equal %w[jessie], VulnerabilityFeed.for("debian").unavailable_releases
    assert_equal [ [ db, %w[docker] ] ], rescanned
  end
end
