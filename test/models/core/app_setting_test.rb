require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  test "default health thresholds" do
    setting = AppSetting.new

    assert_equal [ 80, 90, 90, 95, 2.0 ], setting.attributes.values_at("health_disk_warn", "health_disk_crit", "health_memory_warn", "health_memory_crit", "health_load_warn").map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
    assert setting.valid?
  end

  test "thresholds are percentages, warnings below the critical ones" do
    setting = AppSetting.new(health_disk_warn: 0, health_memory_crit: 101, health_load_warn: 0)
    assert_not setting.valid?
    assert_equal %i[health_disk_warn health_memory_crit health_load_warn].sort, setting.errors.attribute_names.uniq.sort

    setting = AppSetting.new(health_disk_warn: 95, health_disk_crit: 90, health_memory_warn: 95, health_memory_crit: 95)
    assert_not setting.valid?
    assert setting.errors.added?(:health_disk_warn, :less_than, count: 90)
    assert setting.errors.added?(:health_memory_warn, :less_than, count: 95)
  end

  test "inodes and swap thresholds of their own, the swap optional; sustained minutes" do
    setting = AppSetting.new
    assert_equal [ 80, 90, nil, nil, 0 ], setting.attributes.values_at("health_inodes_warn", "health_inodes_crit", "health_swap_warn", "health_swap_crit", "health_sustained_minutes")

    setting = AppSetting.new(health_inodes_warn: 95, health_inodes_crit: 90, health_swap_warn: 80, health_swap_crit: 60, health_sustained_minutes: -1)
    assert_not setting.valid?
    assert setting.errors.added?(:health_inodes_warn, :less_than, count: 90)
    assert setting.errors.added?(:health_swap_warn, :less_than, count: 60)
    assert setting.errors.key?(:health_sustained_minutes)
    assert AppSetting.new(health_swap_warn: 80).valid?, "a warning alone"
  end
end
