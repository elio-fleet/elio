require "test_helper"

class GroupOverviewTest < ActiveSupport::TestCase
  test "each group with its servers most serious first, and how many need handling" do
    servers(:web).update_columns(reachable: true, health_status: "warn")
    servers(:db).update_columns(reachable: false)
    servers(:backup).server_groups << server_groups(:production)
    servers(:backup).update_columns(reachable: true, health_status: "ok")
    loaded = Server.includes(:server_groups).to_a

    overview = GroupOverview.new([ server_groups(:production), server_groups(:staging) ], loaded)

    production, staging = overview.rows
    assert_equal [ servers(:db), servers(:web), servers(:backup) ], production.servers
    assert_equal [ 1, 1 ], [ production.critical, production.to_watch ]
    assert_empty staging.servers
    assert_equal [ 0, 0 ], [ staging.critical, staging.to_watch ]
    assert overview.any?
    assert_not GroupOverview.new([], loaded).any?
  end
end
