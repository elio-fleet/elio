# Manual attachment of an Uptime Kuma probe to a server (or to none), kept
# across synchronizations (IntegrationLink); DELETE returns to the automatic one.
class MonitorLinksController < ApplicationController
  include RequiresIntegration

  requires_integration :uptime_kuma
  require_permission :operate

  before_action :set_monitor

  def create
    server = Server.find(params[:server_id]) if params[:server_id].present?
    @integration.links.find_or_initialize_by(external_id: @monitor.monitor_id).update!(server: server, user: current_user)
    apply(server ? Integrations::UptimeKuma::Matcher::Match.new(server, "manual", nil) : nil, { "key" => "manual_none", "params" => {} })

    redirect_back_or_to monitors_path, notice: server ? t("monitor_links_controller.attached", monitor_name: @monitor.name, server_name: server.name) : t("monitor_links_controller.detached", monitor_name: @monitor.name)
  end

  def destroy
    @integration.links.where(external_id: @monitor.monitor_id).delete_all
    apply_automatic_match

    redirect_back_or_to monitors_path, notice: (@monitor.server ? t("monitor_links_controller.automatic_on", monitor_name: @monitor.name, server_name: @monitor.server.name) : t("monitor_links_controller.automatic", monitor_name: @monitor.name)), status: :see_other
  end

  private

  def set_monitor
    @monitor = UptimeKumaMonitor.find(params[:monitor_id])
  end

  def apply(match, unmatched_reason = {})
    previous = @monitor.server
    @monitor.update!(server: match&.server, matched_by: match&.matched_by, matched_address: match&.address, unmatched_reason: match ? {} : unmatched_reason)
    [ previous, @monitor.server ].compact.uniq.each(&:refresh_health!)
  end

  def apply_automatic_match
    monitor = Integrations::UptimeKuma::Metrics::Monitor.new(
      id: @monitor.monitor_id, name: @monitor.name, monitor_type: @monitor.monitor_type, url: @monitor.url, hostname: @monitor.hostname, port: @monitor.port,
      tags: @monitor.tags, status: @monitor.status, response_time_ms: nil, uptime: {}, average_response_ms: {}, cert_days_remaining: nil, cert_valid: nil
    )
    matcher = Integrations::UptimeKuma.matcher(@integration, Server.includes(:inventory_snapshots).order(:name))
    match = matcher.call(monitor)
    apply(match, match ? {} : matcher.explain(monitor))
  end
end
