# The DNS of the fleet: the records read by the extensions that are DNS
# sources (DnsRecord.source), attached to the servers by Dns::Matcher and
# shown on one DNS page and one DNS tab of the server page.
module Dns
  # The enabled extensions that feed the DNS: [Integration].
  def self.source_integrations
    Integration.enabled_kinds.select { |integration| integration.definition.dns_source?(integration) }
  end

  def self.enabled? = source_integrations.any?
end
