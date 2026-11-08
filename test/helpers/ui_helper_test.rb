require "test_helper"

class UiHelperTest < ActionView::TestCase
  include IconsHelper

  test "status_badge always pairs the colour with an icon and a label" do
    render html: status_badge(:crit, "Critique")

    assert_select "span.badge.bg-crit-soft.text-crit-ink", text: "Critique" do
      assert_select "svg", 1
    end
  end

  test "status_badge without icon" do
    render html: status_badge(:neutral, "Inconnu", class: "extra")

    assert_select "span.badge.extra", text: "Inconnu"
    assert_select "svg", 0
  end

  test "meter colours the fill by threshold and shows the value" do
    render html: meter(50) + meter(85) + meter(94.4, label: "Disque")

    assert_select ".meter", 3
    assert_select ".meter[data-tone=neutral] [role=meter][aria-valuenow='50'] .bg-ink-2[style='width: 50.0%']"
    assert_select ".meter[data-tone=warn] .bg-warn"
    assert_select ".meter[data-tone=crit]" do
      assert_select "span", text: "Disque"
      assert_select "span.text-crit-ink", text: "94\u00A0%"
    end
  end

  test "meter clamps out-of-range values and shows a dash without value" do
    render html: meter(150, value: false) + meter(nil)

    assert_select "[role=meter][aria-valuenow='100']"
    assert_select ".meter span", 0
    assert_select "span.text-ink-3", text: "—"
  end

  test "sparkline draws the values and marks the last point" do
    render html: sparkline([ 0, 50, 100 ], width: 24, height: 12, max: 100, title: "CPU 24 h")

    assert_select "svg.sparkline[role=img][aria-label='CPU 24 h']" do
      assert_select "title", "CPU 24 h"
      assert_select "path[d='M2.0,10.0 L12.0,6.0 L22.0,2.0']"
      assert_select "circle[cx='22.0'][cy='2.0']"
    end
  end

  test "sparkline needs at least two values" do
    render html: sparkline([ 3 ])
    assert_select "svg", 0
    assert_select "span", text: "—"
  end

  test "stat_tile shows a toned figure with its label and caption" do
    render html: stat_tile("Critiques", 3, "dont 1 injoignable", tone: :crit, icon: :x_mark, id: "stat-crit")

    assert_select ".stat-tile#stat-crit" do
      assert_select "p", text: "Critiques"
      assert_select ".stat-value.text-crit-ink", "3"
      assert_select "p", text: "dont 1 injoignable"
    end
  end

  test "sidebar_link marks the active page" do
    render html: sidebar_link("Serveurs", "/servers", icon: :server_stack, active: true, count: 12) +
                 sidebar_link("Clés SSH", "/ssh-keys", icon: :key, active: false) +
                 sidebar_link("Vulnérabilités", "/vulnerabilities", icon: :shield_exclamation, active: false, count: SidebarCounts::Count.new(19, :crit))

    assert_select "a[href='/servers'][aria-current=page].bg-accent-soft", text: /Serveurs\s*12/
    assert_select "a[href='/servers'] .sidebar-count.text-ink-3", "12"
    assert_select "a[href='/ssh-keys']:not([aria-current])", text: "Clés SSH"
    assert_select "a[href='/vulnerabilities'] .sidebar-count.text-crit-ink[data-tone=crit]", "19"
  end

  test "history_chart draws the last 24 hours with a threshold and a tooltip per point" do
    now = Time.zone.parse("2026-10-31 12:00")
    points = [ [ now - 30.hours, 10.0 ], [ now - 12.hours, 40.0 ], [ now, 80.0 ] ]

    render html: history_chart(points, label: "Mémoire", threshold: 90, from: now - 24.hours, to: now)

    assert_select "figure.history-chart" do
      assert_select "figcaption", text: /Mémoire\s*80\u00A0% maintenant/
      assert_select "svg[role=img][aria-label='Mémoire sur 24 heures'] path[d='M50.0,60.0 L100.0,20.0']"
      assert_select "line.chart-threshold[y1='10.0']"
      assert_select "rect.chart-point", 2
      assert_select "rect.chart-point title", "00:00 — 40\u00A0%"
    end
  end

  test "history_chart without any point" do
    render html: history_chart([], label: "Disque")
    assert_select "figcaption", text: /pas encore de mesure/
    assert_select "path", 0
  end
end
