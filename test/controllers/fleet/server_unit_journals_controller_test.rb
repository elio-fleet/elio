require "test_helper"

class ServerUnitJournalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "failed_units" => %w[nginx.service] })
    sign_in users(:viewer)
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
end
