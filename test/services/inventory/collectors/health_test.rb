require "test_helper"

class Inventory::Collectors::HealthTest < ActiveSupport::TestCase
  def parse(name) = Inventory::Collectors::Health.parse(file_fixture("inventory/health/#{name}.txt").read)

  # The commands sent by a collection on a fake Debian server, after the last collection `previous`.
  def collect_commands(previous)
    known_hosts = Rails.root.join("tmp", "test", "health-#{SecureRandom.hex(4)}", "known_hosts")
    handler = lambda do |command|
      if command.include?("os-release") then FakeSsh::Response.new("debian", "", 0)
      elsif command.include?("loadavg") then FakeSsh::Response.new(file_fixture("inventory/health/debian12.txt").read, "", 0)
      end
    end
    fake = FakeSsh.new(handler: handler)
    Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Inventory::Collectors::Health.new(ssh, previous: previous).collect }
    fake.commands
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end

  test "parses a loaded Debian server" do
    data = parse(:debian12)

    assert_equal [ [ 1.92, 1.75, 1.6 ], 8, 24.0 ], data.values_at("load", "cpus", "load_percent")
    assert_equal({ "total" => 32_858_112 * 1024, "available" => 3_942_973 * 1024, "used_percent" => 88.0 }, data["memory"])
    assert_equal 25.0, data.dig("swap", "used_percent")
    assert_equal %w[/ /boot/efi /var/lib/postgresql], data["disks"].map { |disk| disk["mount"] }
    root = data["disks"].first
    assert_equal [ "ext4", 94.4, 1.3, 503_842_392 * 1024 ], root.values_at("type", "used_percent", "inodes_used_percent", "size")
    assert_not data["disks"].second.key?("inodes_used_percent")
    assert_equal 94.4, data["disk_max_percent"]
    assert_equal [ false, [ "fail2ban.service" ], { "total" => 3, "security" => 2 }, true ],
                 data.values_at("reboot_required", "failed_units", "updates", "ntp_synchronized")
  end

  test "the failed units with their description, result and since when (systemctl show, both timestamp formats)" do
    output = file_fixture("inventory/health/debian12.txt").read + <<~TEXT
      @@elio failed_details
      Result=exit-code
      Id=billing-worker.service
      Description=Billing worker
      StateChangeTimestamp=@1763055156

      Id=mnt-backup.mount
      Description=Backup share
      Result=exit-code
      StateChangeTimestamp=Fri 2026-11-13 17:32:36 UTC

      Id=odd.service
      StateChangeTimestamp=n/a
    TEXT
    details = Inventory::Collectors::Health.parse(output)["failed_units_details"]

    assert_equal [ { "name" => "billing-worker.service", "description" => "Billing worker", "result" => "exit-code", "since" => "2025-11-13T17:32:36Z" },
                   { "name" => "mnt-backup.mount", "description" => "Backup share", "result" => "exit-code", "since" => "2026-11-13T17:32:36Z" },
                   { "name" => "odd.service" } ], details
    assert_nil parse(:debian12)["failed_units_details"]
  end

  test "parses an Ubuntu server: mount points with spaces, no swap, reboot required, clock not synchronized" do
    data = parse(:ubuntu2404)

    assert_equal [ "/", "/mnt/backup disk" ], data["disks"].map { |disk| disk["mount"] }
    assert_equal [ 47.8, 92.0 ], data["disks"].first.values_at("used_percent", "inodes_used_percent")
    assert_equal 95.9, data["disk_max_percent"]
    assert_nil data["swap"]
    assert_equal [ true, [], { "total" => 0, "security" => 0 }, false ], data.values_at("reboot_required", "failed_units", "updates", "ntp_synchronized")
  end

  test "keeps what it can from a minimal system without apt" do
    data = parse(:minimal)

    assert_equal [ 0.0, 0.0 ], data.values_at("load_percent", "memory").then { |load, memory| [ load, memory["used_percent"] ] }
    assert_equal [], data["disks"]
    assert_not data.key?("updates")
    assert_not data.key?("ntp_synchronized")
    assert_not data.key?("disk_max_percent")
  end

  test "in a container, the files mounted from the host (/etc/hosts…) are not disks" do
    data = parse(:container)

    assert_equal [ "/srv/data" ], data["disks"].map { |disk| disk["mount"] }
    assert_equal 11.0, data["disk_max_percent"]
  end

  test "the pending updates are stored with the stamp of the package database and when they were computed" do
    now = Time.zone.parse("2026-11-14 10:00")
    data = Inventory::Collectors::Health.parse(file_fixture("inventory/health/debian12.txt").read, now: now)

    assert_equal [ { "total" => 3, "security" => 2 }, "1763012345.1763098765.", "2026-11-14T09:00:00Z" ],
                 data.values_at("updates", "updates_stamp", "updates_checked_at")
  end

  test "an unchanged package database: the updates of the last collection are kept, with when they were computed" do
    output = file_fixture("inventory/health/debian12.txt").read.sub(/^@@elio updates\n(Inst .*\n)+/, "@@elio updates\nunchanged\n")
    previous = { "updates" => { "total" => 7, "security" => 1 }, "updates_stamp" => "1763012345.1763098765.", "updates_checked_at" => "2026-11-14T08:00:00Z" }

    data = Inventory::Collectors::Health.parse(output, previous: previous)
    assert_equal previous.values, data.values_at("updates", "updates_stamp", "updates_checked_at")

    assert_not Inventory::Collectors::Health.parse(output).key?("updates")
  end

  test "processes killed for lack of memory: counted from the second collection, all of them after a reboot, forgotten after 24 hours" do
    health = Inventory::Collectors::Health
    output = ->(count, boot = "boot-a") { "@@elio oom_kill\n#{count}\n@@elio boot_id\n#{boot}\n" }
    now = Time.zone.parse("2026-11-14 10:00")

    first = health.parse(output.(3), now: now)
    assert_equal [ 3, "boot-a", nil ], first.values_at("oom_kills", "boot_id", "oom_kill_events")

    second = health.parse(output.(5), previous: first, now: now + 15.minutes)
    assert_equal [ { "at" => "2026-11-14T09:15:00Z", "count" => 2 } ], second["oom_kill_events"]
    assert_equal second["oom_kill_events"], health.parse(output.(5), previous: second, now: now + 30.minutes)["oom_kill_events"]

    rebooted = health.parse(output.(1, "boot-b"), previous: second, now: now + 1.hour)
    assert_equal [ 2, 1 ], rebooted["oom_kill_events"].pluck("count")

    later = health.parse(output.(1, "boot-b"), previous: rebooted, now: now + 24.hours + 30.minutes)
    assert_equal [ 1 ], later["oom_kill_events"].pluck("count")
    assert_not health.parse("@@elio oom_kill\n@@elio boot_id\n", previous: later).key?("oom_kills")
  end

  test "the apt simulation is skipped when the server has the same stamp as a recent one" do
    previous = { "updates" => { "total" => 7, "security" => 1 }, "updates_stamp" => "1763012345.1763098765.", "updates_checked_at" => 1.hour.ago.utc.iso8601 }

    assert_includes collect_commands(previous).last, "1763012345.1763098765."
    assert_not_includes collect_commands(previous.merge("updates_checked_at" => 7.hours.ago.utc.iso8601)).last, "1763012345.1763098765."
    assert_not_includes collect_commands(previous.merge("updates_stamp" => nil)).last, "1763012345.1763098765."
  end

  test "the stamp sent back to the server cannot break out of its word" do
    dir = Pathname(Dir.mktmpdir)
    dir.join("stat").write("#!/bin/sh\necho 1\n")
    dir.join("stat").chmod(0o755)
    hostile = "1'; touch #{dir}/pwned; echo '$(touch #{dir}/pwned2)"
    command = Ssh::Commands.render("inventory.health", distros: %w[debian], updates_stamp: hostile)

    stdout, = Open3.capture2({ "PATH" => "#{dir}:#{ENV.fetch("PATH")}" }, "sh", "-c", command, err: File::NULL)

    assert_includes stdout, "@@elio updates_stamp\n1.\n"
    assert_not dir.join("pwned").exist?
    assert_not dir.join("pwned2").exist?
  ensure
    FileUtils.rm_rf(dir)
  end

  test "records a point of history" do
    data = parse(:debian12)
    at = Time.zone.parse("2026-10-31 12:00")

    Inventory::Collectors::Health.record(servers(:web), data, at)

    sample = servers(:web).health_samples.sole
    assert_equal [ at, 24.0, 88.0, 94.4 ], [ sample.collected_at, sample.load_percent, sample.memory_percent, sample.disk_percent ]
  end
end
