require "test_helper"

class ServerHealthCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @server = servers(:web)
  end

  def collect(name = :debian12)
    data = Inventory::Collectors::Health.parse(file_fixture("inventory/health/#{name}.txt").read)
    @server.inventory_snapshots.create!(category: "health", status: "ok", data: data, collected_at: 10.minutes.ago, checked_at: 10.minutes.ago)
    @server.health_samples.create!(collected_at: 3.hours.ago, load_percent: 20, memory_percent: 80, disk_percent: 93)
    @server.health_samples.create!(collected_at: 10.minutes.ago, load_percent: 24, memory_percent: 88, disk_percent: 94.4)
    @server.health_samples.create!(collected_at: 3.days.ago, load_percent: 99, memory_percent: 99, disk_percent: 99)
    @server.update_columns(ssh_ok: true, ssh_checked_at: Time.current)
    @server.refresh_health!
  end

  test "shows the figures, what needs attention, the 24-hour history and the disks" do
    collect
    sign_in users(:viewer)

    get server_path(@server)

    assert_select "#server-health-details" do
      assert_select ".health-load", text: /1,92\s+\/ 8 processeurs/
      assert_select ".health-load svg.sparkline"
      assert_select ".health-memory", text: /88\u00A0%\s+27,6 Go \/ 31,3 Go/
      assert_select ".health-disk", text: %r{Disque le plus plein · /\s+94\u00A0%}
      assert_select ".health-disk .text-crit-ink", text: /94\u00A0%/
      assert_select ".health-facts", text: /3 dont 2 de sécurité/
      assert_select ".health-facts", text: /fail2ban\.service/
      assert_select ".history-chart", 3
      assert_select ".history-chart rect.chart-point", 6
      assert_select ".history-chart rect.chart-point title", text: /— 94\u00A0%/
      assert_select ".history-chart line.chart-threshold", 2
      assert_select ".health-disks tbody tr", 3
      assert_select "details#disks-charts .history-chart", 3
    end
    assert_select "#server-attention .health-reasons li.attention-item", 2
    assert_select "#server-attention li.attention-item[data-tone=crit]", text: /Disque \/ à 94\u00A0%/
    assert_select "#server-attention li.attention-item a.attention-action[href=?]", server_path(@server, anchor: "disks"), text: /Voir les disques/
  end

  test "says when there is nothing to report" do
    collect(:minimal)
    sign_in users(:viewer)

    get server_path(@server)

    assert_select "#server-attention", text: /Rien à signaler/
    assert_select "#server-attention li.attention-item", 0
    assert_select "#server-health-details .health-disks", 0
  end

  test "before any measure" do
    sign_in users(:viewer)
    get server_path(@server)
    assert_select "#server-health-details .health-empty"
  end
end
