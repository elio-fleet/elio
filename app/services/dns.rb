# The DNS of the fleet: the records read by the extensions that are DNS
# sources (DnsRecord.source), attached to the servers by Dns::Matcher and
# shown on one DNS page and one DNS tab of the server page.
module Dns
  # The enabled extensions that feed the DNS: [Integration].
  def self.source_integrations
    Integration.enabled_kinds.select { |integration| integration.definition.dns_source?(integration) }
  end

  def self.enabled? = source_integrations.any?

  # "No DNS name" when the alert is on (Settings → Extensions → DNS), once a
  # source has been synchronized, for a server no record of any source
  # points to (its groups can be ignored).
  def self.health_reasons(server, settings: AppSetting.current)
    return [] unless settings.dns_alert_without_name && source_integrations.any?(&:last_synced_at)
    return [] if server.server_groups.any? { |group| settings.dns_without_name_ignored_group_ids.include?(group.id) }
    return [] if server.dns_records.exists?

    [ Inventory::HealthStatus.reason("warn", "dns.health.no_name") ]
  end
end
