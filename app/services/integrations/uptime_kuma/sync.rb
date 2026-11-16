# Stores the probes read from Uptime Kuma (replacing the previous ones),
# attaches them to the servers, logs the alerts enabled in the extension and
# refreshes the health of the servers. Returns a summary.
class Integrations::UptimeKuma::Sync
  def initialize(integration, result)
    @integration = integration
    @result = result
  end

  def call
    records = UptimeKumaMonitor.all.index_by(&:monitor_id)
    # State before this synchronization (the records themselves are updated below).
    previous = records.transform_values { |record| { status: record.status, cert_days_remaining: record.cert_days_remaining } }
    servers = Server.includes(:inventory_snapshots, :server_groups).order(:name).to_a
    matcher = Integrations::UptimeKuma.matcher(@integration, servers, manual_links: @integration.manual_links)
    now = Time.current

    UptimeKumaMonitor.transaction do
      UptimeKumaMonitor.where.not(monitor_id: @result.monitors.map(&:id)).delete_all
      @result.monitors.each do |monitor|
        match = matcher.call(monitor)
        record = records[monitor.id] || UptimeKumaMonitor.new(monitor_id: monitor.id)
        status_changed = record.new_record? || record.status != monitor.status
        record.update!(name: monitor.name, monitor_type: monitor.monitor_type, url: monitor.url, hostname: monitor.hostname, port: monitor.port,
                       tags: monitor.tags, status: monitor.status, response_time_ms: monitor.response_time_ms, uptime: monitor.uptime,
                       average_response_ms: monitor.average_response_ms, cert_days_remaining: monitor.cert_days_remaining, cert_valid: monitor.cert_valid,
                       server: match&.server, matched_by: match&.matched_by, matched_address: match&.address, unmatched_reason: match ? {} : matcher.explain(monitor),
                       status_changed_at: status_changed ? now : record.status_changed_at)
      end
    end

    log_alerts(previous, servers) if @integration.last_synced_at
    Server.refresh_extension_health!(servers)

    attached = UptimeKumaMonitor.attached.count
    without = servers.count { |server| UptimeKumaMonitor.where(server: server).none? }
    I18n.t("integrations.uptime_kuma.sync.summary", monitors: I18n.t("integrations.uptime_kuma.sync.monitors", count: @result.monitors.size), attached: attached, without: I18n.t("integrations.uptime_kuma.sync.without", count: without))
  end

  private

  # Changes since the previous synchronization (never on the first one).
  def log_alerts(previous, servers)
    UptimeKumaMonitor.includes(:server).find_each do |monitor|
      before = previous[monitor.monitor_id]
      next unless before

      if @integration.value(:alert_down)
        if monitor.down? && before[:status] != 0
          Activity.record!(:monitor_down, server: monitor.server, user: nil, monitor: monitor.name)
        elsif before[:status] == 0 && monitor.state == "up"
          Activity.record!(:monitor_up, server: monitor.server, user: nil, monitor: monitor.name)
        end
      end

      threshold = @integration.value(:cert_days).to_i
      if @integration.value(:alert_cert) && monitor.cert_days_remaining && monitor.cert_days_remaining <= threshold &&
         (before[:cert_days_remaining].nil? || before[:cert_days_remaining] > threshold)
        Activity.record!(:monitor_cert_expiring, server: monitor.server, user: nil, monitor: monitor.name, days: monitor.cert_days_remaining)
      end
    end

    log_servers_without_monitor(servers)
  end

  # Once per server, until it gets a probe again.
  def log_servers_without_monitor(servers)
    ignored = Array(@integration.value(:no_monitor_ignored_groups)).map(&:to_i)
    without = servers.select { |server| (server.server_group_ids & ignored).empty? && UptimeKumaMonitor.where(server: server).none? }.map(&:id)
    known = Array(@integration.state["without_monitor"])
    if @integration.value(:alert_no_monitor)
      servers.select { |server| without.include?(server.id) && !known.include?(server.id) }.each do |server|
        Activity.record!(:server_without_monitor, server: server, user: nil)
      end
    end
    @integration.update_columns(state: @integration.state.merge("without_monitor" => without))
  end
end
