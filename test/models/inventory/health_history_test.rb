require "test_helper"

class Inventory::HealthHistoryTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    @now = Time.zone.parse("2026-11-15 12:00")
  end

  def sample(at, load:, memory: 50, disk: 40)
    @server.health_samples.create!(collected_at: at, load_percent: load, memory_percent: memory, disk_percent: disk)
  end

  test "24 hours by default, one point per 5 minutes at its last measure" do
    sample(@now - 2.minutes, load: 10)
    sample(@now - 1.minute, load: 30)
    sample(@now - 3.hours, load: 50)
    sample(@now - 25.hours, load: 99)

    history = Inventory::HealthHistory.new(@server, now: @now)

    assert_equal "24h", history.period.key
    assert_equal @now - 24.hours, history.from
    assert_equal [ [ @now - 3.hours, 50.0, 50.0, 40.0 ], [ @now - 1.minute, 20.0, 50.0, 40.0 ] ], history.points
  end

  test "30 days in 6-hour buckets; an unknown period falls back to 24 hours" do
    sample(Time.utc(2026, 10, 26, 1), load: 10, disk: nil) # buckets start at 0, 6, 12 and 18 h UTC
    sample(Time.utc(2026, 10, 26, 2), load: 20, disk: 60)
    sample(@now - 31.days, load: 99)

    points = Inventory::HealthHistory.new(@server, period: "30d", now: @now).points

    assert_equal 1, points.size
    assert_equal [ 15.0, 50.0, 60.0 ], points.first.drop(1)
    assert_equal "24h", Inventory::HealthHistory.new(@server, period: "1y").period.key
  end

  test "a 7-day history of a minute-by-minute server stays at most one point per hour" do
    rows = (0...(7 * 24 * 60)).step(10).map { |minutes| { server_id: @server.id, collected_at: @now - minutes.minutes, load_percent: 1, memory_percent: 1, disk_percent: 1 } }
    Inventory::HealthSample.insert_all(rows)

    assert_operator Inventory::HealthHistory.new(@server, period: "7d", now: @now).points.size, :<=, 7 * 24 + 1
  end
end
