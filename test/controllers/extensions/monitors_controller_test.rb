require "test_helper"

class MonitorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include StubHelpers
  include UptimeKumaHelpers

  setup do
    sign_in users(:one)
    servers(:web).update_columns(ip_addresses: [ "10.8.0.100" ])
    servers(:web).inventory_snapshots.create!(category: "network", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                               data: { "addresses" => [ { "address" => "10.8.0.100", "interface" => "wg0", "kind" => "wireguard", "scope" => "private" } ] })
    @integration = enable_uptime_kuma
    uptime_kuma_metrics(metrics_page({ id: "1", name: "[SRV] Web ping", hostname: "10.8.0.100", uptime: 0.9962 }, { id: "2", name: "Site vitrine", type: "http", url: "https://www.example.com/", status: 0 }))
    @integration.sync!
  end

  test "404 while the extension is disabled, and no trace of it" do
    @integration.update!(enabled: false)
    get monitors_path
    assert_response :not_found

    sign_in users(:one)
    get server_path(servers(:web), tab: "monitors")
    assert_select "nav.server-tabs a[data-tab=monitors]", 0
    assert_select "#server-monitors", 0
    assert_select "nav.main-nav a", text: "Sondes", count: 0
  end

  test "lists every probe with its server, for every role" do
    sign_in users(:viewer)
    get monitors_path

    assert_response :success
    assert_select "nav.main-nav a[data-integration-link][aria-current=page]", "Sondes"
    assert_select "#stat-monitors .stat-value", "2"
    assert_select "#stat-monitors-down .stat-value", "1"
    assert_select "#stat-unattached .stat-value", "1"
    assert_select "#stat-without .stat-value", "2"
    assert_select "tr.monitor-row", 2
    assert_select "tr.monitor-row[data-state=up] .monitor-server a[href=?]", server_path(servers(:web), tab: "monitors"), text: "Web"
    assert_select "tr.monitor-row[data-state=up] .monitor-server", text: /par son adresse IP/
    assert_select "tr.monitor-row[data-state=up] .monitor-target", text: /via 10\.8\.0\.100 · wg0 \(WireGuard\)/
    assert_select "tr.monitor-row[data-state=up] .monitor-uptime", text: /99,62\u00A0%/
    assert_select "tr.monitor-row a[href='https://uptime.example.test/dashboard/1'][target=_blank]", text: "[SRV] Web ping"
    assert_select "form.monitor-link-form", 0, "viewers cannot attach"
  end

  test "filters: unattached, down, servers without probe, search" do
    get monitors_path(filter: "unattached")
    assert_select "tr.monitor-row", 1
    assert_select "tr.monitor-row", text: /Site vitrine/

    get monitors_path(filter: "down")
    assert_select "tr.monitor-row[data-state=down]", 1

    get monitors_path(filter: "without")
    assert_select "tr.server-without-monitor", 2
    assert_select "tr.server-without-monitor", text: /Database/

    get monitors_path(q: "vitrine")
    assert_select "tr.monitor-row", 1
  end

  test "a probe can be attached by hand, kept across syncs, then back to automatic" do
    monitor = UptimeKumaMonitor.find_by!(monitor_id: "2")
    post monitor_link_path(monitor), params: { server_id: servers(:db).id }
    assert_equal [ servers(:db), "manual" ], monitor.reload.then { [ _1.server, _1.matched_by ] }
    assert_match "rattachée à « Database »", flash[:notice]

    @integration.reload.sync!
    assert_equal servers(:db), monitor.reload.server

    delete monitor_link_path(monitor)
    assert_nil monitor.reload.server
    assert_empty @integration.links.reload

    web_probe = UptimeKumaMonitor.find_by!(monitor_id: "1")
    post monitor_link_path(web_probe), params: { server_id: "" }
    assert_nil web_probe.reload.server
    delete monitor_link_path(web_probe)
    assert_equal [ servers(:web), "ip" ], web_probe.reload.then { [ _1.server, _1.matched_by ] }
  end

  test "attaching is for operators" do
    sign_in users(:viewer)
    post monitor_link_path(UptimeKumaMonitor.first), params: { server_id: servers(:db).id }
    assert_response :forbidden
  end

  test "the server tab lists its probes" do
    get server_path(servers(:web), tab: "monitors")
    assert_select "nav.server-tabs a[data-tab=monitors][aria-current=page]", text: /Sondes\s*1/
    assert_select "#server-monitors tr.monitor-row", 1
    assert_select "#server-monitors form.monitor-link-form select option[selected]", "Web"

    get server_path(servers(:db), tab: "monitors")
    assert_select "#server-monitors .monitors-empty", text: /Aucune sonde ne surveille ce serveur/
    assert_select "#server-monitors .monitors-empty a[href=?]", monitors_path(filter: "unattached")
  end

  test "the settings page of the extension shows its fields and help" do
    get edit_settings_integration_path("uptime_kuma")
    assert_select ".integration-help", text: /Clés API/
    assert_select "input[name='integration[values][url]'][value='https://uptime.example.test']"
    assert_select "input[type=checkbox][name='integration[values][no_monitor_ignored_groups][]']", ServerGroup.count
    assert_select "select[name='integration[values][uptime_window]'] option[selected][value='30d']"
  end

  test "the fleet list has no probe column: the probes are on the server page and the Probes page" do
    get servers_path
    assert_select "#servers th", text: "Sondes", count: 0
    assert_select ".server-monitors", 0
  end

  test "the number of queries does not grow with the number of probes (AUDIT.md D1)" do
    count_queries = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get monitors_path }
      queries
    end
    few = count_queries.call

    uptime_kuma_metrics(metrics_page(*Array.new(30) { |index| { id: (100 + index).to_s, name: "Sonde #{index}", hostname: "10.8.0.100" } }))
    @integration.reload.sync!
    many = count_queries.call

    assert_operator many - few, :<=, 3, "#{few} queries for 2 probes, #{many} for 30"
  end

  test "quick search lists the probes page" do
    get root_path
    assert_includes response.body, %("label":"Sondes","hint":"extension","url":"/monitors")
  end

  test "the Monitors tab offers a prompt for an AI, for every role" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "monitors")
    assert_select "#server-monitors .server-prompt[data-kind=monitors]" do
      assert_select "button.server-prompt-button", /Prompt pour proposer des sondes/
      assert_select "dialog textarea.server-prompt-text[readonly]", /Je surveille mes serveurs Linux avec Uptime Kuma.*\[SRV\] Web ping/m
      assert_select "button[data-action='clipboard#copy']"
    end
  end
end
