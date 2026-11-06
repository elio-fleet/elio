# Uptime Kuma: reads the probes from its /metrics page (API key, read-only),
# attaches each one to the server it watches (Integrations::UptimeKuma::Matcher)
# and raises the alerts chosen in the extension's settings.
class Integrations::UptimeKuma < Integrations::Base
  self.key = "uptime_kuma"
  self.label = "Uptime Kuma"
  self.icon = :signal
  self.default_interval = 15

  WINDOWS = %w[1d 30d 365d].freeze # labels: integrations.uptime_kuma.windows.w<window>

  class << self
    def fields
      [
        Integrations::Field.new(key: :url, label: I18n.t("integrations.uptime_kuma.url"), type: :url, required: true, placeholder: "https://uptime.example.com",
                  hint: I18n.t("integrations.uptime_kuma.url_hint")),
        Integrations::Field.new(key: :api_key, label: I18n.t("integrations.uptime_kuma.api_key"), secret: true, required: true, hint: I18n.t("integrations.uptime_kuma.api_key_hint")),
        Integrations::Field.new(key: :allow_self_signed, label: I18n.t("integrations.uptime_kuma.self_signed"), type: :boolean, default: false,
                  hint: I18n.t("integrations.uptime_kuma.self_signed_hint")),

        Integrations::Field.new(key: :match_by_ip, label: I18n.t("integrations.uptime_kuma.match_by_ip"), type: :boolean, default: true, section: I18n.t("integrations.uptime_kuma.section_matching"),
                  hint: I18n.t("integrations.uptime_kuma.match_by_ip_hint")),
        Integrations::Field.new(key: :match_by_host, label: I18n.t("integrations.uptime_kuma.match_by_host"), type: :boolean, default: true, section: I18n.t("integrations.uptime_kuma.section_matching"),
                  hint: I18n.t("integrations.uptime_kuma.match_by_host_hint")),
        Integrations::Field.new(key: :resolve_dns, label: I18n.t("integrations.uptime_kuma.resolve_dns"), type: :boolean, default: false, section: I18n.t("integrations.uptime_kuma.section_matching"),
                  hint: I18n.t("integrations.uptime_kuma.resolve_dns_hint")),
        Integrations::Field.new(key: :match_by_name, label: I18n.t("integrations.uptime_kuma.match_by_name"), type: :boolean, default: true, section: I18n.t("integrations.uptime_kuma.section_matching"),
                  hint: I18n.t("integrations.uptime_kuma.match_by_name_hint")),

        Integrations::Field.new(key: :alert_no_monitor, label: I18n.t("integrations.uptime_kuma.alert_no_monitor"), type: :boolean, default: true, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :no_monitor_ignored_groups, label: I18n.t("integrations.uptime_kuma.ignored_groups"), type: :checkboxes, default: [], section: I18n.t("integrations.sections.alerts"),
                  options: ServerGroup.order(:name).map { |group| [ group.id.to_s, group.name ] }),
        Integrations::Field.new(key: :alert_down, label: I18n.t("integrations.uptime_kuma.alert_down"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts"),
                  hint: I18n.t("integrations.uptime_kuma.alert_down_hint")),
        Integrations::Field.new(key: :alert_cert, label: I18n.t("integrations.uptime_kuma.alert_cert"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :cert_days, label: I18n.t("integrations.uptime_kuma.cert_days"), type: :number, default: 14, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :alert_uptime, label: I18n.t("integrations.uptime_kuma.alert_uptime"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :uptime_threshold, label: I18n.t("integrations.uptime_kuma.uptime_threshold"), type: :number, default: 99, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :uptime_window, label: I18n.t("integrations.uptime_kuma.uptime_window"), type: :select, options: WINDOWS.map { |window| [ I18n.t("integrations.uptime_kuma.windows.w#{window}"), window ] }, default: "30d", section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :alert_maintenance, label: I18n.t("integrations.uptime_kuma.alert_maintenance"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :maintenance_days, label: I18n.t("integrations.uptime_kuma.maintenance_days"), type: :number, default: 7, section: I18n.t("integrations.sections.alerts"))
      ]
    end

    def test_connection(integration)
      result = fetch(integration)
      message = I18n.t("integrations.uptime_kuma.found", count: result.monitors.size) + (result.version ? " (Uptime Kuma #{result.version})" : "")
      message += I18n.t("integrations.uptime_kuma.http_warning") if integration.value(:url).to_s.start_with?("http://")
      message
    end

    def sync(integration)
      result = fetch(integration)
      Integrations::UptimeKuma::Sync.new(integration, result).call
    end

    def server_tabs = [ { key: "monitors", label: I18n.t("integrations.uptime_kuma.monitors"), count: ->(server) { server.uptime_kuma_monitors.size } } ]

    def sidebar_links = [ { label: I18n.t("integrations.uptime_kuma.monitors"), path: :monitors_path, icon: :signal, controller: "monitors" } ]

    def help_partial = "integrations/uptime_kuma/help"

    def health_reasons(integration, server)
      return [] unless integration.last_synced_at

      monitors = server.uptime_kuma_monitors.to_a
      reasons = []
      if monitors.empty?
        ignored = Array(integration.value(:no_monitor_ignored_groups)).map(&:to_i)
        reasons << reason("warn", :no_monitor) if integration.value(:alert_no_monitor) && (server.server_group_ids & ignored).empty?
        return reasons
      end

      monitors.each do |monitor|
        reasons << reason("crit", :monitor_down, name: monitor.name) if integration.value(:alert_down) && monitor.down?
        if integration.value(:alert_cert) && monitor.cert_days_remaining && monitor.cert_days_remaining <= integration.value(:cert_days).to_i
          reasons << reason(monitor.cert_days_remaining <= 0 || monitor.cert_valid == false ? "crit" : "warn",
                            *(monitor.cert_days_remaining <= 0 ? [ :cert_expired, { name: monitor.name } ] : [ :cert_expiring, { name: monitor.name, count: monitor.cert_days_remaining } ]))
        end
        window = integration.value(:uptime_window)
        ratio = monitor.uptime_ratio(window)
        if integration.value(:alert_uptime) && ratio && ratio * 100 < integration.value(:uptime_threshold).to_f
          reasons << reason("warn", :uptime, name: monitor.name, window_key: "integrations.uptime_kuma.windows.w#{window}", ratio: (ratio * 100).round(2))
        end
        if integration.value(:alert_maintenance) && monitor.state == "maintenance" && monitor.status_changed_at &&
           monitor.status_changed_at < integration.value(:maintenance_days).to_i.days.ago
          reasons << reason("warn", :maintenance, name: monitor.name, count: integration.value(:maintenance_days).to_i)
        end
      end
      reasons
    end

    def fetch(integration)
      result = Integrations::Http.get("#{integration.value(:url).to_s.chomp("/")}/metrics", service: "Uptime Kuma", basic_auth: [ "", integration.value(:api_key).to_s ],
                                      verify_ssl: !integration.value(:allow_self_signed))
      parsed = Integrations::UptimeKuma::Metrics.parse(result)
      raise Integrations::Error, I18n.t("integrations.uptime_kuma.not_metrics") if parsed.monitors.empty? && parsed.version.nil?

      parsed
    end

    private

    def reason(tone, key, params = {}, **more) = Inventory::HealthStatus.reason(tone, "integrations.uptime_kuma.health.#{key}", **params, **more)
  end
end
