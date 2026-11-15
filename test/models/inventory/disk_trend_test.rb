require "test_helper"

class Inventory::DiskTrendTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    @now = Time.zone.parse("2026-11-15 12:00")
  end

  # One sample every 6 hours over the last `days`, the disk growing by
  # `per_day` points a day up to `current` now.
  def fill(days:, per_day:, current:)
    (0..(days * 4)).each do |step|
      @server.health_samples.create!(collected_at: @now - (step * 6).hours, load_percent: 10, memory_percent: 10, disk_percent: current - per_day * step / 4.0)
    end
  end

  def trend = Inventory::DiskTrend.new(@server, now: @now)

  test "a disk growing 2 points a day at 80 % is full in about 10 days" do
    fill(days: 6, per_day: 2, current: 80)

    assert_in_delta 10, trend.days_left, 0.01
    assert_equal :warn, trend.tone
    assert_equal Date.new(2026, 11, 25), trend.full_on
  end

  test "a disk full in less than a week is critical" do
    fill(days: 3, per_day: 5, current: 90)

    assert_in_delta 2, trend.days_left, 0.01
    assert_equal :crit, trend.tone
  end

  test "nothing for a stable or shrinking disk, nor further than the horizon" do
    fill(days: 6, per_day: 0, current: 50)
    assert_nil trend.days_left

    @server.health_samples.delete_all
    fill(days: 6, per_day: -1, current: 50)
    assert_nil trend.days_left

    @server.health_samples.delete_all
    fill(days: 6, per_day: 0.1, current: 50)
    assert_nil trend.days_left
    assert_nil trend.tone
  end

  test "nothing with less than a day of history or too few samples" do
    fill(days: 0, per_day: 10, current: 90)
    assert_nil trend.days_left

    @server.health_samples.create!(collected_at: @now - 2.days, load_percent: 1, memory_percent: 1, disk_percent: 50)
    assert_nil trend.days_left, "two samples are not a trend"
  end

  test "only the last 7 days count" do
    fill(days: 6, per_day: 2, current: 80)
    @server.health_samples.create!(collected_at: @now - 20.days, load_percent: 1, memory_percent: 1, disk_percent: 99)

    assert_in_delta 10, trend.days_left, 0.01
  end
end
