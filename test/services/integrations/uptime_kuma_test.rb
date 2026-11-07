require "test_helper"

class Integrations::UptimeKumaTest < ActiveSupport::TestCase
  include StubHelpers
  include UptimeKumaHelpers

  setup do
    servers(:web).update_columns(ip_addresses: [ "10.8.0.100" ])
    @integration = enable_uptime_kuma
  end

  test "registered, with its automation, only available while enabled" do
    assert_equal "Integrations::UptimeKuma", Integration.registry["uptime_kuma"]
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "uptime_kuma_sync" }
    assert automation.available?
    @integration.update!(enabled: false)
    assert_not automation.available?
  end

  test "test_connection reads /metrics with the API key" do
    uptime_kuma_metrics
    assert_equal "2 sondes trouvées (Uptime Kuma 2.5.6)", Integrations::UptimeKuma.test_connection(@integration)
    url, options = @uptime_kuma_requests.sole
    assert_equal [ "https://uptime.example.test/metrics", [ "", "uk-key" ], true, "Uptime Kuma" ], [ url, options[:basic_auth], options[:verify_ssl], options[:service] ]

    @integration.assign_form("url" => "https://uptime.example.test/", "allow_self_signed" => "1")
    Integrations::UptimeKuma.test_connection(@integration)
    assert_equal [ "https://uptime.example.test/metrics", false ], [ @uptime_kuma_requests.last.first, @uptime_kuma_requests.last.last[:verify_ssl] ]
  end

  test "test_connection warns when the API key would travel in clear (http)" do
    uptime_kuma_metrics
    @integration.assign_form("url" => "http://uptime.internal:3001")
    assert_match "⚠ Adresse en http : la clé API circule en clair", Integrations::UptimeKuma.test_connection(@integration)
  end

  test "a page that is not Uptime Kuma's /metrics" do
    uptime_kuma_metrics("<html>Login</html>")
    error = assert_raises(Integrations::Error) { Integrations::UptimeKuma.test_connection(@integration) }
    assert_match "ne ressemble pas", error.message
  end

  test "sync stores the probes, attaches them and summarizes" do
    uptime_kuma_metrics
    assert_equal "2 sondes, 1 rattachée(s) ; 2 serveurs sans sonde", @integration.sync!

    utils = UptimeKumaMonitor.find_by!(monitor_id: "64")
    assert_equal [ servers(:web), "ip", "10.8.0.100" ], [ utils.server, utils.matched_by, utils.matched_address ]
    assert_equal({ "1d" => 1.0, "30d" => 1.0, "365d" => 1.0 }, utils.uptime)
    assert_nil UptimeKumaMonitor.find_by!(monitor_id: "58").server
  end

  test "Uptime Kuma 1.x (no monitor_id): the probes keep the same record from one sync to the next" do
    servers(:web).update_columns(ip_addresses: [ "192.0.2.44" ])
    uptime_kuma_metrics(file_fixture("integrations/uptime_kuma/metrics_v1.txt").read)
    assert_equal "3 sondes, 2 rattachée(s) ; 2 serveurs sans sonde", @integration.sync!, "by IP, and « bench-target web » by the name Web"
    vpn = UptimeKumaMonitor.find_by!(monitor_id: "name:Old VPN gateway")
    assert_equal [ servers(:web), "ip" ], [ vpn.server, vpn.matched_by ]

    assert_no_difference -> { UptimeKumaMonitor.count } do
      @integration.sync!
    end
    assert_equal vpn.id, UptimeKumaMonitor.find_by!(monitor_id: "name:Old VPN gateway").id
  end

  test "a probe gone from Uptime Kuma is removed; a manual link is kept across syncs" do
    uptime_kuma_metrics(metrics_page({ id: "1", name: "A", hostname: "10.8.0.100" }, { id: "2", name: "B" }))
    @integration.links.create!(external_id: "2", server: servers(:db))
    @integration.links.create!(external_id: "1", server: nil)
    @integration.sync!

    assert_nil UptimeKumaMonitor.find_by!(monitor_id: "1").server, "refused by hand"
    assert_equal [ servers(:db), "manual" ], UptimeKumaMonitor.find_by!(monitor_id: "2").then { [ _1.server, _1.matched_by ] }

    uptime_kuma_metrics(metrics_page({ id: "2", name: "B" }))
    @integration.sync!
    assert_equal [ "2" ], UptimeKumaMonitor.pluck(:monitor_id)
  end

  test "alerts: probe down and back, certificate, server without probe — only when enabled, never on the first sync" do
    @integration.update!(settings: @integration.settings.merge("alert_down" => true, "alert_cert" => true, "cert_days" => 14))
    uptime_kuma_metrics(metrics_page({ id: "1", name: "Web ping", hostname: "10.8.0.100", status: 1, cert_days: 30 }))
    @integration.sync!
    assert_equal 0, Activity.where(kind: %w[monitor_down monitor_up monitor_cert_expiring]).count
    assert_equal 0, Activity.of_kind(:server_without_monitor).count, "nothing on the first sync"

    uptime_kuma_metrics(metrics_page({ id: "1", name: "Web ping", hostname: "10.8.0.100", status: 0, cert_days: 10 }))
    @integration.reload.sync!
    assert_equal [ "Sonde « Web ping » hors ligne (Web)" ], Activity.of_kind(:monitor_down).map(&:summary)
    assert_equal 1, Activity.of_kind(:monitor_cert_expiring).count
    assert_equal %w[Backup Database], Activity.of_kind(:server_without_monitor).map { _1.server.name }.sort

    uptime_kuma_metrics(metrics_page({ id: "1", name: "Web ping", hostname: "10.8.0.100", status: 1, cert_days: 9 }))
    @integration.reload.sync!
    assert_equal 1, Activity.of_kind(:monitor_up).count
    assert_equal 1, Activity.of_kind(:monitor_cert_expiring).count, "once, when it crosses the threshold"
    assert_equal 2, Activity.of_kind(:server_without_monitor).count, "once per server"
  end

  test "health reasons, each alert enabled in the settings" do
    uptime_kuma_metrics(metrics_page({ id: "1", name: "Web ping", hostname: "10.8.0.100", status: 0, cert_days: 3, uptime: 0.95 }))
    @integration.sync!
    reasons = ->(server) { Integrations::UptimeKuma.health_reasons(@integration.reload, server).map { |reason| [ reason.tone, reason.text ] } }

    assert_equal [ [ "warn", "Aucune sonde Uptime Kuma" ] ], reasons.(servers(:db))
    assert_empty reasons.(servers(:web)), "the other alerts are off by default"

    @integration.update!(settings: @integration.settings.merge("alert_down" => true, "alert_cert" => true, "alert_uptime" => true, "uptime_threshold" => 99,
                                                                 "no_monitor_ignored_groups" => [ server_groups(:production).id.to_s ]))
    assert_equal [ [ "crit", "Sonde « Web ping » hors ligne" ], [ "warn", "Certificat de « Web ping » : expire dans 3 j" ],
                   [ "warn", "Disponibilité de « Web ping » sur 30 jours : 95,00\u00A0%" ] ], reasons.(servers(:web))
    assert_empty reasons.(servers(:db)), "Database is in an ignored group"
    assert_equal "crit", servers(:web).reload.tap(&:refresh_health!).health_status
  end

  test "no reason before the first synchronization" do
    assert_empty Integrations::UptimeKuma.health_reasons(@integration, servers(:db))
  end
end
