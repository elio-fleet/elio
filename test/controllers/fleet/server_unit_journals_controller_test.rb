require "test_helper"

class ServerUnitJournalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "failed_units" => %w[nginx.service] })
    sign_in users(:operator)
  end

  test "a viewer cannot read a journal: its lines carry addresses, users, keys" do
    sign_in users(:viewer)
    stub_method(Inventory::UnitJournal, :call, ->(*) { flunk "no SSH" }) do
      get server_unit_journal_path(servers(:web), unit: "nginx.service")
    end
    assert_response :forbidden
  end

  test "shows the last lines of the journal of a failed unit in its frame" do
    journal = Inventory::UnitJournal::Result.new(lines: [ "nginx[812]: bind() to 0.0.0.0:80 failed", "<script>alert(1)</script>" ], error: nil)
    asked = nil
    stub_method(Inventory::UnitJournal, :call, ->(server, unit) { (asked = [ server, unit ]) && journal }) do
      get server_unit_journal_path(servers(:web), unit: "nginx.service")
    end

    assert_response :success
    assert_equal [ servers(:web), "nginx.service" ], asked
    assert_select "turbo-frame[id^=unit_journal_] pre", text: /bind\(\) to 0\.0\.0\.0:80 failed\n<script>alert\(1\)<\/script>/
    assert_select "script", text: "alert(1)", count: 0
    assert_select "turbo-frame", text: /Les 2 dernières lignes du journal/
  end

  test "says why the journal could not be read" do
    stub_method(Inventory::UnitJournal, :call, Inventory::UnitJournal::Result.new(lines: [], error: "Permission denied")) do
      get server_unit_journal_path(servers(:web), unit: "nginx.service")
    end

    assert_select ".unit-journal-error", text: /Journal illisible : Permission denied/
  end

  test "nothing is sent to the server for a unit that is not failed, or not a unit name" do
    stub_method(Inventory::UnitJournal, :call, ->(*) { flunk "no SSH" }) do
      get server_unit_journal_path(servers(:web), unit: "ssh.service")
      assert_response :not_found
      get server_unit_journal_path(servers(:web), unit: "nginx.service; reboot")
      assert_response :not_found
      get server_unit_journal_path(servers(:web))
      assert_response :not_found
    end
  end

  test "reads the journal of the service a timer starts: the output of its last runs" do
    servers(:web).inventory_snapshots.create!(category: "scheduled_tasks", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "cron" => [], "periodic" => [], "timers" => [ { "name" => "backup.timer", "unit" => "backup.service" } ] })
    asked = nil
    stub_method(Inventory::UnitJournal, :call, ->(_server, unit) { (asked = unit) && Inventory::UnitJournal::Result.new(lines: [ "backup.sh[901]: 3 databases saved" ], error: nil) }) do
      get server_unit_journal_path(servers(:web), unit: "backup.service")
      assert_response :success
      assert_select "turbo-frame pre", text: /3 databases saved/
      get server_unit_journal_path(servers(:web), unit: "backup.timer")
      assert_response :not_found
    end

    assert_equal "backup.service", asked
  end
end
