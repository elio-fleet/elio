require "test_helper"

# A new installation, or a server upgraded to a new release, gets its
# vulnerabilities right after its inventory, not at the next daily download.
class Vulnerabilities::CoverTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include VulnerabilityHelpers
  include InventoryHelpers
  include StubHelpers

  class TrixieCollector < Inventory::Collector
    def collect = ok({ "id" => "debian", "codename" => "trixie" })
  end

  setup do
    @server = servers(:web)
    @update = Automation.all_kinds.find { |automation| automation.kind == "vulnerabilities_update" }
  end

  def cover = Vulnerabilities.cover(@server)

  test "a release that the feed does not hold yet: the download runs now, followed on the Tasks page" do
    record_os(@server, codename: "trixie")
    VulnerabilityFeed.for("debian").update!(refreshed_at: 2.days.ago, releases: %w[bookworm])

    assert_enqueued_with(job: RunAutomationJob) { assert_difference("BackgroundTask.count") { cover } }
    assert_equal @update, BackgroundTask.last.automation
    assert_no_enqueued_jobs(only: RunAutomationJob) { cover } # already waiting: not twice
  end

  test "a first installation: no feed downloaded yet" do
    record_os(@server, codename: "trixie")
    assert_enqueued_jobs(1, only: RunAutomationJob) { cover }
  end

  test "nothing when the release is held, after a failure, when the feed has no such release, when disabled, or on another system" do
    record_os(@server, codename: "trixie")
    feed = VulnerabilityFeed.for("debian")

    feed.update!(refreshed_at: 2.days.ago, releases: %w[trixie])
    assert_no_enqueued_jobs { cover }

    feed.update!(releases: [], failed_at: 1.minute.ago)
    assert_no_enqueued_jobs { cover } # a closed network: not at every inventory

    feed.update!(failed_at: nil, refreshed_at: 10.minutes.ago, unavailable_releases: %w[trixie])
    assert_no_enqueued_jobs { cover } # the last download did not find it: not at every inventory

    feed.update!(unavailable_releases: [])

    feed.update!(refreshed_at: 2.days.ago)
    @update.update!(enabled: false)
    assert_no_enqueued_jobs { cover } # turned off on purpose

    @update.update!(enabled: true)
    record_os(@server, id: "alpine", codename: nil)
    assert_no_enqueued_jobs { cover }
  end

test "a Docker image on another release than the servers: the download runs now" do
  record_os(@server, codename: "trixie")
  @server.inventory_snapshots.create!(category: "docker", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                      data: { "images" => [ { "reference" => "nginx:1.25", "os" => { "id" => "debian", "codename" => "bookworm" } } ] })
  @server.inventory_snapshots.reset
  VulnerabilityFeed.for("debian").update!(refreshed_at: 5.minutes.ago, releases: %w[trixie])

  assert_equal [ %w[debian trixie], %w[debian bookworm] ], Vulnerabilities.targets_of(@server)
  assert_enqueued_jobs(1, only: RunAutomationJob) { cover }
end

test "an inventory that reads the system covers the server" do
    covered = []
    stub_method(Vulnerabilities, :cover, ->(server) { covered << server }) do
      with_collectors("os" => "Vulnerabilities::CoverTest::TrixieCollector") do
        Inventory::Collection.call(@server, categories: %w[os], transport: FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", 0) }),
                                            known_hosts_file: Rails.root.join("tmp", "test", "cover-#{SecureRandom.hex(4)}"))
      end
    end
    assert_equal [ @server ], covered
  end

  test "new CVEs on the fleet get their scores now; known ones wait for the next run" do
    scores = Automation.all_kinds.find { |automation| automation.kind == "cve_scores_update" }
    stub_method(Vulnerabilities::Update, :call, "ok") do
      @server.server_vulnerabilities.create!(source: "debian", cve: "CVE-2024-6387", source_package: "openssh", severity: "high")
      assert_enqueued_with(job: RunAutomationJob, args: ->(args) { args.first == scores }) { @update.run! }

      clear_enqueued_jobs
      BackgroundTask.update_all(status: "succeeded")
      CveScore.create!(cve: "CVE-2024-6387", provider_key: "nvd", fetched_at: Time.current)
      assert_no_enqueued_jobs(only: RunAutomationJob) { @update.run! }
    end
  end
end
