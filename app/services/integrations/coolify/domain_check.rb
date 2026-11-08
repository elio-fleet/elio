# The domains Coolify serves on a server, checked against the DNS of the
# fleet (DnsRecord: OVHcloud, Technitium, Gandi): :ok (a record attached to
# this server), :elsewhere (records, none attached to this server: another
# server, an IP outside the fleet, a CNAME Elio cannot follow), :missing (no
# record although its zone is known), :unknown (a zone Elio does not read).
class Integrations::Coolify::DomainCheck
  Domain = Data.define(:name, :resource, :state, :records) do
    def targets = records.map(&:value).uniq.sort
  end

  def initialize(server)
    @server = server
  end

  def domains
    @domains ||= begin
      pairs = @server.coolify_resources.select { |resource| CoolifyResource::RESOURCE_KINDS.include?(resource.kind) }.sort_by(&:name)
                     .flat_map { |resource| resource.domains.filter_map { |domain| (name = self.class.host(domain)) && [ name, resource ] } }.uniq(&:first)
      records = DnsRecord.where(name: pairs.map(&:first), disabled: false).to_a.group_by(&:name)
      zones = DnsRecord.distinct.pluck(:zone)
      pairs.map { |name, resource| Domain.new(name: name, resource: resource, state: state(name, records[name], zones), records: records[name] || []) }
    end
  end

  def problems = domains.select { |domain| domain.state.in?(%i[elsewhere missing]) }

  def for(resource) = domains.select { |domain| domain.resource == resource }

  # "app.example.com:8080/path" → "app.example.com"; nil for a wildcard or an IP.
  def self.host(domain)
    name = domain.to_s.downcase.split("/").first.to_s.split(":").first.to_s.chomp(".")
    name if name.include?(".") && !name.start_with?("*") && !Inventory::IpScope.ip?(name)
  end

  private

  def state(name, records, zones)
    return records.any? { |record| record.server_id == @server.id } ? :ok : :elsewhere if records.present?

    zones.any? { |zone| name == zone || name.end_with?(".#{zone}") } ? :missing : :unknown
  end
end
