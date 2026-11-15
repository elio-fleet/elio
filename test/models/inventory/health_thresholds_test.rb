require "test_helper"

class Inventory::HealthThresholdsTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    @settings = AppSetting.current
  end

  def thresholds = Inventory::HealthThresholds.new(@server.reload, @settings)

  test "the settings without anything of the server or its groups; the swap not watched" do
    assert_equal [ 80, 90, 80, 90, 90, 95, nil, nil ], thresholds.values.values_at(*%w[disk_warn disk_crit inodes_warn inodes_crit memory_warn memory_crit swap_warn swap_crit])
    assert_equal 2.0, thresholds.load_warn.to_f
  end

  test "the server first, else the strictest of its groups, else the settings" do
    @server.server_groups << server_groups(:staging)
    server_groups(:production).update!(health_thresholds: { "disk_warn" => "70", "memory_warn" => "85" })
    server_groups(:staging).update!(health_thresholds: { "disk_warn" => "60", "disk_crit" => "95" })
    @server.update!(health_thresholds: { "memory_warn" => "50", "load_warn" => "1,5" })

    values = thresholds.values
    assert_equal [ 60, 95, 50, 95, 1.5 ], values.values_at("disk_warn", "disk_crit", "memory_warn", "memory_crit", "load_warn")
    assert_equal 85, thresholds.inherited("memory_warn"), "the hint of the server's form: what it would have without its own"
  end

  test "a form keeps only the thresholds set, as numbers" do
    @server.health_thresholds = { "disk_warn" => " 85 ", "disk_crit" => "", "load_warn" => "2,5", "unknown" => "1" }
    assert_equal({ "disk_warn" => 85, "load_warn" => 2.5 }, @server.health_thresholds)
  end

  test "refuses a threshold out of range, not a number, or a warning not below its critical" do
    assert_predicate @server.tap { |server| server.health_thresholds = { "disk_warn" => "85", "disk_crit" => "95", "load_warn" => "3" } }, :valid?

    [ { "disk_warn" => "0" }, { "memory_crit" => "101" }, { "load_warn" => "60" }, { "swap_warn" => "abc" } ].each do |values|
      @server.health_thresholds = values
      assert_not @server.valid?, values.inspect
      assert @server.errors.added?(:health_thresholds, :health_threshold_range), values.inspect
    end

    group = server_groups(:production)
    group.health_thresholds = { "inodes_warn" => "95", "inodes_crit" => "90" }
    assert_not group.valid?
    assert_equal [ "Les seuils de santé doivent avoir chaque seuil d'attention sous son seuil critique" ], group.errors.full_messages
  end
end
