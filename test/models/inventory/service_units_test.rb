require "test_helper"

class Inventory::ServiceUnitsTest < ActiveSupport::TestCase
  def unit(name, active, **details) = { "name" => name, "active" => active, "sub" => (active == "active" ? "running" : "dead") }.merge(details.stringify_keys)

  setup do
    units = [ unit("ssh.service", "active", description: "OpenBSD Secure Shell server"), unit("nginx.service", "inactive", type: "forking", enabled: "enabled"),
              unit("e2scrub_reap.service", "inactive", type: "oneshot", enabled: "enabled"), unit("exim4.service", "inactive", type: "forking", enabled: "disabled"),
              unit("fail2ban.service", "failed") ]
    servers(:web).inventory_snapshots.create!(category: "services", status: "ok", data: { "units" => units }, collected_at: Time.current, checked_at: Time.current)
  end

  def names(units) = units.map { |unit| unit["name"] }

  test "a stopped unit starts at boot, is not running, and is not a one-shot task" do
    list = Inventory::ServiceUnits.new(servers(:web))

    assert_equal %w[fail2ban.service], names(list.failed)
    assert_equal %w[ssh.service], names(list.active)
    assert_equal %w[nginx.service], names(list.stopped)
    assert_equal %w[e2scrub_reap.service exim4.service], names(list.other_inactive)
    assert_equal [ 5, 1, 1, 3 ], [ list.count, list.count("active"), list.count("failed"), list.count("inactive") ]
    assert_not list.filtered?
  end

  test "filters by state, searches the name and the description, ignores an unknown state" do
    assert_equal [ [], [], %w[nginx.service] ], Inventory::ServiceUnits.new(servers(:web), state: "inactive").then { |list| [ names(list.failed), names(list.active), names(list.stopped) ] }

    list = Inventory::ServiceUnits.new(servers(:web), query: " secure SHELL ")
    assert_equal [ %w[ssh.service], [], 1 ], [ names(list.active), names(list.other_inactive), list.count ]
    assert list.filtered?

    list = Inventory::ServiceUnits.new(servers(:web), state: "everything")
    assert_nil list.state
    assert_equal 5, (list.failed + list.active + list.stopped + list.other_inactive).size
  end
end
