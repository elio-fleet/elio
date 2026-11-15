require "test_helper"

class Inventory::FailedUnitsTest < ActiveSupport::TestCase
  def record(category, data)
    servers(:web).inventory_snapshots.create!(category: category, status: "ok", collected_at: Time.current, checked_at: Time.current, data: data)
  end

  test "the services inventory first, with since when; then the units only the health reading saw" do
    record("services", "units" => [ { "name" => "nginx.service", "active" => "failed" }, { "name" => "ssh.service", "active" => "active" } ])
    record("health", "failed_units" => %w[nginx.service mnt-backup.mount],
                     "failed_units_details" => [ { "name" => "nginx.service", "since" => "2026-11-13T10:00:00Z" },
                                                 { "name" => "mnt-backup.mount", "description" => "Backup share", "since" => "2026-11-12T08:00:00Z" } ])

    failed = Inventory::FailedUnits.new(servers(:web))

    assert_equal [ [ "nginx.service", "2026-11-13T10:00:00Z", nil ], [ "mnt-backup.mount", "2026-11-12T08:00:00Z", "Backup share" ] ],
                 failed.units.map { |unit| unit.values_at("name", "since", "description") }
    assert_nil failed.units.first["seen_at"], "listed by the services inventory"
    assert failed.units.last["seen_at"]
    assert_equal 2, failed.count
  end

  test "a unit that failed within minutes of the boot failed at boot; one that failed later did not" do
    record("os", "booted_at" => "2026-11-12T08:00:00Z")
    record("health", "failed_units" => %w[mnt-backup.mount nginx.service old.service],
                     "failed_units_details" => [ { "name" => "mnt-backup.mount", "since" => "2026-11-12T08:01:30Z" },
                                                 { "name" => "nginx.service", "since" => "2026-11-13T10:00:00Z" },
                                                 { "name" => "old.service", "since" => "2026-11-11T10:00:00Z" } ])

    failed = Inventory::FailedUnits.new(servers(:web))
    assert_equal [ true, false, nil ], failed.units.map { |unit| unit["at_boot"] },
                 "a failure older than the known boot: the system inventory is out of date, nothing said"
    assert_equal %w[mnt-backup.mount nginx.service old.service], failed.names
  end

  test "without the boot time, nothing is said about the boot" do
    record("health", "failed_units" => %w[nginx.service], "failed_units_details" => [ { "name" => "nginx.service", "since" => "2026-11-13T10:00:00Z" } ])
    assert_not Inventory::FailedUnits.new(servers(:web)).units.first.key?("at_boot")
  end

  test "nothing read yet: no failed unit" do
    assert_equal 0, Inventory::FailedUnits.new(servers(:web)).count
  end
end
