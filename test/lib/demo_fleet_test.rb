require "test_helper"
require "rake"
require Rails.root.join("lib/elio/demo_fleet")

class DemoFleetTest < ActiveSupport::TestCase
  test "builds the demo fleet without the network: servers, inventories, vulnerabilities, extensions, DNS, notes" do
    Server.delete_all
    fleet = Elio::DemoFleet.new
    built = fleet.build_core
    fleet.build_extensions_offline(built[:web], built[:db])
    fleet.build_dns_and_firewall(built[:db])
    fleet.build_notes(built[:db], admin: users(:one), operator: users(:operator))

    assert_equal %w[backup db-prod monitoring staging web-prod-1 web-prod-2 worker-1], Server.order(:name).pluck(:name)
    assert built[:db].inventory("docker").collected?
    assert_operator built[:db].server_vulnerabilities.count, :>, 50
    assert_equal %w[coolify gandi manual_dns ovh technitium uptime_kuma], Integration.where(enabled: true).pluck(:kind).sort
    assert DnsRecord.exists?(source: "gandi", server: built[:web])
    assert DnsRecord.exists?(name: "worker.office.example.internal", server: Server.find_by!(name: "worker-1")), "the manual source is attached"
    assert_equal 2, built[:db].notes.count
  end

  test "dev:demo runs in development only" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("dev:demo")
    error = assert_raises(SystemExit) { capture_io { Rake::Task["dev:demo"].execute } }
    assert_not error.success?
  end
end
