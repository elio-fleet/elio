# A probe of Uptime Kuma (see Integrations::UptimeKuma), attached to the
# server it watches when one matches.
class UptimeKumaMonitor < ApplicationRecord
  STATUSES = { 1 => "up", 0 => "down", 2 => "pending", 3 => "maintenance" }.freeze
  MATCHES = %w[ip url dns name manual].freeze # labels: uptime_kuma_monitor.matches.*

  belongs_to :server, optional: true

  scope :attached, -> { where.not(server_id: nil) }
  scope :unattached, -> { where(server_id: nil) }
  scope :by_name, -> { order(Arel.sql("LOWER(uptime_kuma_monitors.name)")) }

  def state = STATUSES.fetch(status, "unknown")
  def down? = status == 0

  # What the probe checks: its host name / IP (and port), or its URL.
  def target = hostname ? [ hostname, port ].compact.join(":") : url

  # The probe among `monitors` that checks `host` (its host name, or the host of its URL), or nil.
  def self.for_host(monitors, host)
    return if host.blank?

    monitors.find { |monitor| [ monitor.hostname, monitor.url_host ].any? { |value| value.to_s.casecmp?(host) } }
  end

  def url_host
    URI.parse(url.to_s).host
  rescue URI::InvalidURIError
    nil
  end

  def uptime_ratio(window) = uptime[window.to_s]

  # Whether the instance publishes the uptime of its monitors in /metrics
  # (monitor_uptime_ratio): Uptime Kuma 1.23 and 2.0 do not, and then the
  # uptime column and alert have nothing to show.
  def self.uptime_published? = where.not(uptime: {}).exists?

  # Link to the probe in Uptime Kuma.
  # (nil unless the instance address is http(s): never a javascript: link)
  def dashboard_url(base_url) = Integration.http_url?(base_url) ? "#{base_url.to_s.chomp("/")}/dashboard/#{monitor_id.to_i}" : nil
end
