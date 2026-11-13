# The DNS of the fleet: the records read by the extensions that are DNS
# sources (DnsRecord.source), attached to the servers by Dns::Matcher and
# shown on one DNS page and one DNS tab of the server page.
module Dns
  # The enabled extensions that feed the DNS: [Integration]. Asked several
  # times per page (sidebar, tabs, ⌘K): read once per request (Current).
  def self.source_integrations
    Current.dns_sources ||= Integration.enabled_kinds.select { |integration| integration.definition.dns_source?(integration) }
  end

  def self.enabled? = source_integrations.any?

  # Every source of records, one per extension and one per manual source
  # (Integrations::ManualDns connection): its DnsRecord.source, its label,
  # its synchronization state and the extension it belongs to.
  Source = Data.define(:key, :label, :last_synced_at, :last_error, :integration)

  def self.sources
    source_integrations.flat_map do |integration|
      if integration.kind == Integrations::ManualDns.key
        integration.connections.sort_by(&:label).map do |connection|
          Source.new(Integrations::ManualDns.source(connection), connection.label, connection.last_synced_at, connection.last_error, integration)
        end
      else
        [ Source.new(integration.kind, DnsRecord.source_label(integration.kind), integration.last_synced_at, integration.last_error, integration) ]
      end
    end
  end

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
