require "test_helper"

class Inventory::Collectors::ScheduledTasksTest < ActiveSupport::TestCase
  Collector = Inventory::Collectors::ScheduledTasks
  NOW = Time.zone.at(1_762_000_000)

  def output(name) = file_fixture("inventory/scheduled_tasks/#{name}.txt").read

  def collect(name, sudo: true)
    known_hosts = Rails.root.join("tmp", "test", "tasks-#{SecureRandom.hex(4)}", "known_hosts")
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", sudo ? 0 : 1) },
                       handler: ->(command) { FakeSsh::Response.new(output(name), "", 0) if command.include?("sh -c") })
    [ Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: known_hosts) { |ssh| Collector.new(ssh).collect }, fake.commands ]
  ensure
    FileUtils.rm_rf(known_hosts.dirname)
  end

  test "reads the system and users' crontabs, skipping comments and variables" do
    cron = Collector.parse(output(:debian13), now: NOW)["cron"]

    assert_equal 10, cron.size
    assert_equal({ "source" => "/etc/crontab", "user" => "root", "schedule" => "25 6 * * *",
                   "command" => "test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.daily; }" }, cron[1])
    assert_equal({ "source" => "/etc/cron.d/pg-backup", "user" => "postgres", "schedule" => "15 2 * * *",
                   "command" => "/usr/local/bin/backup.sh --all >> /var/log/pg-backup.log 2>&1" }, cron.find { |task| task["source"].end_with?("pg-backup") })
    assert_equal [ [ "crontab de root", "root", "*/5 * * * *", "/root/bin/check-disk.sh" ], [ "crontab de root", "root", "@reboot", "/root/bin/warmup.sh" ],
                   [ "crontab de deploy", "deploy", "0 */6 * * *", "cd /srv/app && ./bin/rails runner 'Cleanup.run' >/dev/null" ] ],
                 cron.last(3).map { |task| task.values_at("source", "user", "schedule", "command") }
  end

  test "lists the periodic scripts" do
    periodic = Collector.parse(output(:debian13), now: NOW)["periodic"]
    assert_equal [ %w[daily apt-compat], %w[daily dpkg], %w[daily logrotate], %w[daily man-db], %w[weekly man-db] ], periodic.map { |task| task.values_at("period", "name") }
  end

  test "reads the timers with their last run, result and next run; flags failed and late ones" do
    timers = Collector.parse(output(:debian13), now: NOW)["timers"].index_by { |timer| timer["name"] }

    assert_equal %w[apt-daily-upgrade.timer certbot.timer backup.timer systemd-tmpfiles-clean.timer fstrim.timer], timers.keys
    apt = timers["apt-daily-upgrade.timer"]
    assert_equal [ "apt-daily-upgrade.service", [ "OnCalendar=*-*-* 06:00:00" ], Time.zone.at(1_761_973_203).iso8601, "success", "enabled" ],
                 apt.values_at("unit", "schedules", "last_at", "result", "enabled")
    assert_not apt.key?("failed")
    assert_not apt.key?("late")

    assert_equal [ true, "exit-code", 1 ], timers["certbot.timer"].values_at("failed", "result", "exit_status")
    assert timers["backup.timer"]["late"], "last run 3 days ago for a daily timer"
    assert_equal [ "OnBootUSec=15min", "OnUnitActiveUSec=1d" ], timers["systemd-tmpfiles-clean.timer"]["schedules"]
    assert_not timers["systemd-tmpfiles-clean.timer"].key?("late")
    assert_equal [ "inactive", nil, nil ], timers["fstrim.timer"].values_at("active", "last_at", "late")
  end

  test "a server that was off is not late: systemd catches up after booting (real DB-2 case)" do
    output = file_fixture("inventory/scheduled_tasks/debian13.txt").read.sub("864000.52", "360.0")
    assert_not Collector.parse(output, now: NOW)["timers"].find { |timer| timer["name"] == "backup.timer" }.key?("late"), "up for 6 minutes"
  end

  test "a next run long overdue makes a timer late" do
    timers = Collector.parse(output(:no_root), now: Time.zone.parse("2025-11-03 12:00"))["timers"]
    assert timers.sole["late"]
    assert_equal Time.zone.parse("2025-11-01 00:00:03 CET").iso8601, timers.sole["last_at"]
  end

  test "collects through sudo, partial when the users' crontabs cannot be read" do
    outcome, commands = collect(:debian13)
    assert_equal [ "ok", "ok" ], [ outcome.status, outcome.data["user_crontabs"] ]
    assert_includes commands, "sudo -n #{Ssh::Commands.render("inventory.scheduled_tasks")}"

    outcome, = collect(:no_root, sudo: false)
    assert_equal "partial", outcome.status
    assert_match "Crontabs des utilisateurs illisibles", outcome.message
    assert_equal 1, outcome.data["cron"].size
  end

  test "a system without cron nor systemd is unsupported" do
    assert_equal "unsupported", collect(:none).first.status
  end

  test "logs the timers that start failing or are late" do
    previous = { "timers" => [ { "name" => "certbot.timer" }, { "name" => "backup.timer", "late" => true } ] }
    data = Collector.parse(output(:debian13), now: NOW)

    assert_equal [ { kind: :scheduled_task_failed, data: { task: "certbot.timer" } } ], Collector.changes(previous, data)
    assert_empty Collector.changes(data, data)
  end

  test "logs the tasks that disappear: enabled timers, cron lines (by command) and cron.* scripts" do
    previous = Collector.parse(output(:debian13), now: NOW)
    data = previous.deep_dup
    backup = data["cron"].find { |task| task["command"].include?("backup.sh") }
    data["cron"].delete(backup)
    data["timers"].reject! { |timer| timer["name"].in?(%w[backup.timer systemd-tmpfiles-clean.timer fstrim.timer]) }
    data["periodic"].reject! { |task| task["name"] == "logrotate" }
    data["cron"].first["schedule"] = "0 4 * * *"

    removed = Collector.changes(previous, data).select { |change| change[:kind] == :scheduled_task_removed }.map { |change| change[:data][:task] }

    # The static and disabled timers are pulled in by other units: not a removal. A new schedule neither.
    assert_equal [ "#{backup["command"]} (#{backup["source"]})", "/etc/cron.daily/logrotate", "backup.timer" ].sort, removed
  end

  test "what a reading could not see is not a removal: users' crontabs without root, no timer listed" do
    previous = Collector.parse(output(:debian13), now: NOW)
    users = previous["cron"].reject { |task| task["source"].start_with?("/") }
    assert users.any?

    without_root = previous.merge("cron" => previous["cron"] - users, "user_crontabs" => "unreadable")
    assert_empty Collector.changes(previous, without_root).select { |change| change[:kind] == :scheduled_task_removed }
    assert_empty Collector.changes(without_root, previous).select { |change| change[:kind] == :scheduled_task_removed }

    assert_empty Collector.changes(previous, previous.merge("timers" => [])).select { |change| change[:kind] == :scheduled_task_removed }
  end

  test "a user's crontab line is compared by its user, not by its translated label" do
    previous = Collector.parse(output(:debian13), now: NOW)
    data = I18n.with_locale(:en) { Collector.parse(output(:debian13), now: NOW) }

    assert_not_equal previous["cron"].map { |task| task["source"] }, data["cron"].map { |task| task["source"] }
    assert_empty Collector.changes(previous, data).select { |change| change[:kind] == :scheduled_task_removed }
  end

  test "failed and late timers are health reasons" do
    server = servers(:web)
    server.inventory_snapshots.create!(category: "scheduled_tasks", status: "ok", collected_at: NOW, checked_at: NOW,
                                       data: Collector.parse(output(:debian13), now: NOW))

    texts = Inventory::HealthStatus.evaluate(server.reload).reasons.map(&:text)
    assert_includes texts, "Tâche planifiée certbot en échec"
    assert_includes texts, "Tâche planifiée backup en retard"
  end

  test "real output of DB-2 (Debian 13, just rebooted after 3 days off): nothing is late" do
    data = Collector.parse(output(:"debian13-real"), now: Time.zone.parse("2026-11-01 13:33"))

    assert_equal [ 10, 7, 8, "ok" ], [ data["cron"].size, data["periodic"].size, data["timers"].size, data["user_crontabs"] ]
    assert_empty data["timers"].select { |timer| timer["late"] || timer["failed"] }.map { |timer| timer["name"] }
    man_db = data["timers"].find { |timer| timer["name"] == "man-db.timer" }
    assert_equal [ "2026-10-29T16:37:33+01:00", [ "OnCalendar=*-*-* 00:00:00" ] ], man_db.values_at("last_at", "schedules")
    assert_includes data["cron"].map { |task| Inventory::CronSchedule.cron(task["schedule"]).text }, "toutes les 10 minutes à partir de :05"
  end
end
