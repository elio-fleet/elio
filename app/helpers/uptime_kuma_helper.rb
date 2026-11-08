# Display of the Uptime Kuma probes (UptimeKumaMonitor).
module UptimeKumaHelper
  # Tone of each state (labels: uptime_kuma_helper.states.*).
  MONITOR_STATES = { "up" => :good, "down" => :crit, "pending" => :warn, "maintenance" => :neutral, "unknown" => :neutral }.freeze

  def monitor_status_badge(monitor)
    status_badge(MONITOR_STATES.fetch(monitor.state), t("uptime_kuma_helper.states.#{monitor.state}"), class: "monitor-status", data: { state: monitor.state })
  end

  # 0.99625 → "99,63 %"
  def uptime_percent(ratio)
    return tag.span("—", class: "text-ink-3") unless ratio

    percent = ratio * 100
    text = number_to_percentage(percent, precision: percent >= 99.995 ? 0 : 2)
    tag.span(text, class: "tabular-nums #{percent < 99 ? "text-warn-ink" : ""}")
  end

  # Which address of the server the probe reaches: "10.8.0.100 · wg0 (VPN)".
  def monitor_via(monitor)
    return unless monitor.server

    address = monitor.matched_address || (monitor.hostname if Inventory::IpScope.ip?(monitor.hostname))
    interface = address && Array(monitor.server.inventory("network")&.data&.dig("addresses")).find { |entry| entry["address"] == address }
    return if address.nil? || (interface.nil? && address == monitor.hostname) # (nothing more than the target)

    [ address, (interface && "#{interface["interface"]} (#{interface_kind_label(interface["kind"])})") ].compact.join(" · ")
  end

  def monitor_match_label(monitor) = monitor.matched_by.presence && t("uptime_kuma_monitor.matches.#{monitor.matched_by}", default: "")

  # Probes attached by hand (to a server or to none), read once per page.
  def manual_monitor_ids
    @manual_monitor_ids ||= IntegrationLink.joins(:integration).where(integrations: { kind: "uptime_kuma" }).pluck(:external_id).to_set
  end
end
