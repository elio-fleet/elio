require "test_helper"

class AutomationTest < ActiveSupport::TestCase
  include StubHelpers

  test "all_kinds creates every automation once, with its default interval; only the health check, the vulnerability feeds and scores, the image checks (and the extensions' syncs) are on" do
    automations = Automation.all_kinds

    assert_equal %w[health_check servers_ping inventory_os inventory_packages inventory_services inventory_ports vulnerabilities_update cve_scores_update docker_image_updates
                    keys_scan uptime_kuma_sync ovh_sync technitium_sync gandi_sync], automations.map(&:kind)
    assert_equal [ 15, 15, 1440, 360, 60, 60, 1440, 360, 360, 360, 15, 360, 60, 60 ], automations.map(&:interval_minutes)
    assert_equal %w[health_check vulnerabilities_update cve_scores_update docker_image_updates uptime_kuma_sync ovh_sync technitium_sync gandi_sync], automations.select(&:enabled?).map(&:kind)
    assert_equal automations, Automation.all_kinds
    assert_equal 14, Automation.count
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
end
