require "test_helper"

class AutomationTest < ActiveSupport::TestCase
  include StubHelpers

  test "all_kinds creates every automation once, with its default interval, all on: a new installation collects everything on schedule" do
    automations = Automation.all_kinds

    assert_equal %w[health_check servers_ping inventory_os inventory_packages inventory_services inventory_ports vulnerabilities_update cve_scores_update docker_image_updates
                    keys_scan uptime_kuma_sync ovh_sync technitium_sync gandi_sync coolify_sync], automations.map(&:kind)
    assert_equal [ 15, 15, 1440, 360, 60, 60, 1440, 360, 360, 360, 15, 360, 60, 60, 15 ], automations.map(&:interval_minutes)
    assert_equal automations.map(&:kind), automations.select(&:enabled?).map(&:kind)
    assert_equal automations, Automation.all_kinds
    Automation.find_by(kind: "keys_scan").update!(enabled: false)
    assert_not Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }.enabled?, "an existing choice is kept"
    assert_equal 15, Automation.count
    assert_equal %w[health_check servers_ping inventory_os inventory_packages inventory_services inventory_ports vulnerabilities_update cve_scores_update docker_image_updates keys_scan],
                 Automation.available.map(&:kind),
                 "an extension's sync only shows once it is enabled"
  end

  test "validations" do
    automation = Automation.new(kind: "nope", interval_minutes: 7)
    assert_not automation.valid?
    assert automation.errors.key?(:kind)
    assert automation.errors.key?(:interval_minutes)

    Automation.all_kinds
    assert_not Automation.new(kind: "keys_scan", interval_minutes: 60).valid?
  end

  test "due? and next_run_at" do
    automation = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    automation.update!(enabled: false)
    freeze_time do
      assert_not automation.due?
      assert_nil automation.next_run_at

      automation.update!(enabled: true, interval_minutes: 60)
      assert automation.due?
      assert_equal Time.current, automation.next_run_at

      automation.update!(last_run_at: 59.minutes.ago)
      assert_not automation.due?
      assert_equal 1.minute.from_now, automation.next_run_at

      automation.update!(last_run_at: 60.minutes.ago)
      assert automation.due?
    end
  end

  test "the keys scan scans every server and counts the new keys without public_key" do
    automation = Automation.all_kinds.find { |a| a.kind == "keys_scan" }
    scan = lambda do |server, **|
      Activity.record!(:unknown_key_detected, server: server) if server.name == "Web"
      Keys::ServerScan::Result.new(error_title: (server.name == "Backup" ? "Connexion impossible" : nil))
    end

    result = stub_method(Keys::ServerScan, :call, scan) { automation.run! }

    assert_equal "2/3 serveurs scannés, 1 nouvelle clé inconnue", result
    assert_equal result, automation.reload.last_result
    assert_not_nil automation.last_run_at
    activity = Activity.of_kind(:automation_run).sole
    assert_equal "Scan des clés : #{result}", activity.summary
    assert_equal "Système", activity.author_name
  end

  test "the servers check pings every server" do
    automation = Automation.all_kinds.find { |a| a.kind == "servers_ping" }

    result = stub_method(Servers::Ping, :check_all!, ->(servers, **) { servers.to_a.index_with { |server| server.name != "Database" } }) { automation.run! }

    assert_equal "2/3 serveurs joignables", result
  end

  def snapshot(server, unix_user, *public_keys)
    AccountSnapshot.create!(server: server, unix_user: unix_user, read_at: 1.minute.ago,
                            content: public_keys.map { |public_key| public_key.content }.join("\n"))
  end

  test "inventory automations collect their categories on their servers, a few at a time" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_ports" }
    automation.update!(server_group_ids: [ server_groups(:production).id ])
    calls = Concurrent::Array.new
    collection = lambda do |server, categories:|
      calls << [ server.name, categories ]
      { "ports" => Inventory::Collector::Outcome.new(status: server.name == "Web" ? "error" : "ok", data: {}, message: nil) }
    end

    result = stub_method(Inventory::Collection, :call, collection) { automation.run! }

    assert_equal [ [ "Database", %w[ports] ], [ "Web", %w[ports] ] ], calls.sort
    assert_equal "1/2 serveurs inventoriés", result
    assert_equal "Inventaire des ports : 1/2 serveurs inventoriés", Activity.of_kind(:automation_run).sole.summary
    assert_equal "Production", automation.scope_label
  end

  test "frequent automations do not log their runs" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "health_check" }

    assert_no_difference("Activity.of_kind(:automation_run).count") do
      stub_method(Inventory::Collection, :call, ->(*, **) { {} }) { automation.run! }
    end
    assert_equal "3/3 serveurs inventoriés", automation.reload.last_result
  end

  test "scope: the groups, or the whole fleet" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "keys_scan" }
    assert_equal %w[Backup Database Web], automation.servers.map(&:name)
    assert_equal "Tout le parc", automation.scope_label

    automation.update!(server_group_ids: [ "", server_groups(:production).id.to_s, server_groups(:production).id.to_s ])
    assert_equal [ server_groups(:production).id ], automation.server_group_ids
    assert_equal %w[Database Web], automation.servers.map(&:name)
  end

  test "hours: a scheduled run starts only within them, over midnight too" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_packages" }
    automation.update!(window_start_hour: 22, window_end_hour: 6, last_run_at: 2.days.ago)
    assert_equal "De 22:00 à 06:00", automation.window_label

    travel_to Time.zone.parse("2026-11-14 12:00") do
      assert_not automation.in_window?
      assert_not automation.due?
      assert_equal Time.zone.parse("2026-11-14 22:00"), automation.next_run_at
    end
    travel_to(Time.zone.parse("2026-11-14 23:30")) { assert automation.due? }
    travel_to(Time.zone.parse("2026-11-15 05:59")) { assert automation.due? }
    travel_to(Time.zone.parse("2026-11-15 06:00")) { assert_not automation.due? }

    automation.update!(window_start_hour: 1, window_end_hour: 5)
    travel_to Time.zone.parse("2026-11-14 12:00") do
      assert_equal Time.zone.parse("2026-11-15 01:00"), automation.next_run_at, "after today's hours: tomorrow"
    end
    travel_to(Time.zone.parse("2026-11-14 03:00")) { assert automation.due? }
  end

  test "hours: none means at any time, the same hour twice is refused" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_packages" }
    automation.update!(window_start_hour: "", window_end_hour: "6")
    assert_nil automation.window_end_hour, "no start hour: at any time"
    assert_equal "À toute heure", automation.window_label
    travel_to(Time.zone.parse("2026-11-14 12:00")) { assert automation.in_window? }

    automation.window_start_hour = 6
    assert_not automation.valid?
    assert automation.errors.key?(:window_end_hour)
    automation.window_start_hour = 24
    assert automation.errors.key?(:window_start_hour) unless automation.valid?
  end

  test "groups left out: their servers are not part of the run" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "keys_scan" }
    ServerGroupMembership.create!(server: servers(:backup), server_group: server_groups(:staging))

    automation.update!(excluded_server_group_ids: [ "", server_groups(:production).id.to_s ])
    assert_equal %w[Backup], automation.servers.map(&:name)
    assert_equal "Tout le parc sauf Production", automation.scope_label

    automation.update!(server_group_ids: [ server_groups(:production).id, server_groups(:staging).id ], excluded_server_group_ids: [ server_groups(:staging).id ])
    assert_equal %w[Database Web], automation.servers.map(&:name)
    assert_equal "Production, Staging sauf Staging", automation.scope_label
  end

  test "each run keeps its duration, the last ones only" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "cve_scores_update" }
    automation.update!(run_durations: Array.new(Automation::DURATIONS_KEPT, 3.0))

    stub_method(Vulnerabilities::Scores, :update_all, -> { "ok" }) { automation.run! }

    assert_equal Automation::DURATIONS_KEPT, automation.reload.run_durations.size
    assert_operator automation.last_duration, :<, 3
  end

  test "an unreachable server is tried again after a wait as long as it has been down, unless a check saw it answer" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_ports" }
    web, db, backup = servers(:web), servers(:db), servers(:backup)
    freeze_time do
      # Database: down for 3 hours, tried an hour ago → waits until 2 hours from now.
      db.update_columns(inventoried_at: 3.hours.ago, reachable: false)
      db.inventory_snapshots.create!(category: "ports", status: "error", checked_at: 1.hour.ago)
      # Backup: the same, but the ping has seen it answer since.
      backup.update_columns(inventoried_at: 3.hours.ago, reachable: true, last_checked_at: 10.minutes.ago)
      backup.inventory_snapshots.create!(category: "ports", status: "error", checked_at: 1.hour.ago)
      # Web: connected, only the collector failed.
      web.update_columns(inventoried_at: 1.hour.ago)
      web.inventory_snapshots.create!(category: "ports", status: "error", checked_at: 1.hour.ago)
      calls = Concurrent::Array.new
      collection = ->(server, **) { calls << server.name; { "ports" => Inventory::Collector::Outcome.new(status: "ok", data: {}, message: nil) } }

      result = stub_method(Inventory::Collection, :call, collection) { automation.run! }

      assert_equal %w[Backup Web], calls.sort
      assert_equal "2/3 serveurs inventoriés, 1 serveur injoignable réessayé plus tard", result

      calls.clear
      travel 2.hours
      stub_method(Inventory::Collection, :call, collection) { automation.run! }
      assert_includes calls, "Database", "the wait is over"

      calls.clear
      task = automation.enqueue!(user: users(:one))
      db.inventory_snapshots.find_by!(category: "ports").update!(status: "error", checked_at: Time.current)
      stub_method(Inventory::Collection, :call, collection) { automation.run!(task: task) }
      assert_includes calls, "Database", "a run started by hand tries every server"
    end
  end
end
