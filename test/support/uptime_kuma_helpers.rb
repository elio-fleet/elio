# Uptime Kuma extension in tests: enabled with a fake instance whose /metrics
# page is the recorded one (or the given text); never the network.
module UptimeKumaHelpers
  METRICS_URL = "https://uptime.example.test/metrics"

  def enable_uptime_kuma(**settings)
    Integration.find_or_initialize_by(kind: "uptime_kuma").tap do |integration|
      integration.update!(enabled: true, settings: { "url" => "https://uptime.example.test" }.merge(settings.stringify_keys), secrets: { "api_key" => "uk-key" })
    end
  end

  def uptime_kuma_metrics(text = file_fixture("integrations/uptime_kuma/metrics_v2.txt").read)
    @uptime_kuma_requests = []
    stub_method_until_teardown(Integrations::Http, :get, lambda { |url, **options|
      @uptime_kuma_requests << [ url, options ]
      text.respond_to?(:call) ? text.call : text
    })
  end

  # A /metrics page with the given probes: { id:, name:, hostname:, url:, status:, cert_days:, tags: { "server" => "vmdb1" } }.
  def metrics_page(*monitors)
    monitors.flat_map do |monitor|
      labels = %(monitor_id="#{monitor[:id]}",monitor_name="#{monitor[:name]}",monitor_type="#{monitor.fetch(:type, "ping")}",monitor_url="#{monitor.fetch(:url, "https://")}",monitor_hostname="#{monitor.fetch(:hostname, "null")}",monitor_port="null")
      labels = [ *monitor.fetch(:tags, {}).map { |name, value| %(#{name}="#{value}") }, labels ].join(",")
      [ "monitor_status{#{labels}} #{monitor.fetch(:status, 1)}",
        ("monitor_cert_days_remaining{#{labels}} #{monitor[:cert_days]}" if monitor[:cert_days]),
        ("monitor_uptime_ratio{#{labels},window=\"30d\"} #{monitor[:uptime]}" if monitor[:uptime]) ].compact
    end.join("\n") + %(\napp_version{version="2.5.6",major="2",minor="5",patch="6"} 1\n)
  end
end
