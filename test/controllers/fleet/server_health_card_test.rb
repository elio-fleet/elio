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

  test "each reason says since when it has been there, when the journal knows" do
    collect
    disk = @server.health_reasons.find { |reason| reason["key"] == "health.disk" }
    Activity.create!(kind: "health_critical", server: @server, data: { reasons: [ disk ] }, created_at: 2.days.ago)
    sign_in users(:viewer)

    get server_path(@server)

    assert_select "#server-attention li.attention-item[data-tone=crit] time.attention-since", text: "apparu il y a 2 jours"
    assert_select "#server-attention time.attention-since", 2
  end

  test "says when there is nothing to report" do
    collect(:minimal)
    sign_in users(:viewer)

    get server_path(@server)

    assert_select "#server-attention", text: /Rien à signaler/
    assert_select "#server-attention li.attention-item", 0
    assert_select "#server-health-details .health-disks", 0
  end

  test "the charts over 7 or 30 days, opened on the chosen period" do
    collect
    sign_in users(:viewer)

    get server_path(@server)
    assert_select "details#disks-charts:not([open])"
    assert_select ".chart-periods a.filter-chip[aria-current=true]", text: "24 h"
    assert_select ".history-chart rect.chart-point", 6

    get server_path(@server, period: "7d")
    assert_select "details#disks-charts[open]"
    assert_select ".chart-periods a.filter-chip[aria-current=true][href=?]", server_path(@server, period: "7d", anchor: "disks-charts"), text: "7 jours"
    assert_select ".history-chart svg[aria-label='Mémoire sur 7 jours']"
    assert_select ".history-chart", text: /il y a 7 jours/
    assert_select ".history-chart rect.chart-point", 9
    assert_select ".health-load svg.sparkline path", 1, "the sparklines stay on 24 hours"
  end

  test "the fullest disk says when it will be full at its recent pace" do
    collect
    @server.health_samples.delete_all
    (0..12).each { |step| @server.health_samples.create!(collected_at: (step * 6).hours.ago, load_percent: 10, memory_percent: 10, disk_percent: 94.4 - step * 0.5) }
    sign_in users(:viewer)

    get server_path(@server)

    assert_select ".health-disk .disk-trend.text-crit-ink", text: "plein dans environ 3 jours"
  end

  test "no disk trend without enough history" do
    collect
    sign_in users(:viewer)
    get server_path(@server)
    assert_select ".disk-trend", 0
  end

  test "the latest events of the server, newest first, with a link to the journal" do
    Activity.record!(:server_created, server: @server, user: nil, address: "root@web:22")
    Activity.record!(:server_updated, server: @server, user: nil)
    Activity.record!(:server_created, server: servers(:db), user: nil, address: "root@db:22")
    sign_in users(:viewer)

    get server_path(@server)

    assert_select "#server-latest-events" do
      assert_select "li.activity", 2
      assert_select "li.activity:first-child[data-kind=server_updated]"
      assert_select "a[href=?]", server_path(@server, tab: "journal", show: "events"), text: "Tous les événements"
    end
  end

  test "no event yet" do
    sign_in users(:viewer)
    get server_path(@server)
    assert_select "#server-latest-events", text: /Aucun événement pour ce serveur/
  end

  test "before any measure" do
    sign_in users(:viewer)
    get server_path(@server)
    assert_select "#server-health-details .health-empty"
  end
end
