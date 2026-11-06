# Attaches OVHcloud resources to the servers: a manual link first, then by
# address (an IP block containing an address of the server), by the service
# an IP block is routed to, by name (service reverse / name = host name or
# server name). The DNS records are attached by Dns::Matcher.
class Integrations::Ovh::Matcher
  Match = Data.define(:server, :matched_by, :address)

  ORDER = %w[dedicated vps instance ip].freeze

  def initialize(servers, manual_links: {})
    @directory = ServerDirectory.new(servers)
    @by_id = @directory.servers.index_by(&:id)
    @manual_links = manual_links
  end

  # { resource (Fetch::Resource) => Match or nil }
  def call(resources)
    matches = {}
    services = {}
    resources.sort_by { |resource| ORDER.index(resource.kind) || ORDER.size }.each do |resource|
      match = manual(resource) || by_address(resource) || by_service(resource, services) || by_name(resource)
      matches[resource] = match == :none ? nil : match
      services[resource.data["service"] || resource.external_id] = matches[resource] if resource.kind.in?(%w[dedicated vps])
    end
    matches
  end

  private

  def key(resource) = "#{resource.kind}:#{resource.external_id}"

  def manual(resource)
    return unless @manual_links.key?(key(resource))

    server = @by_id[@manual_links[key(resource)]]
    server ? Match.new(server, "manual", nil) : :none
  end

  def by_address(resource)
    resource.addresses.each do |value|
      found = @directory.by_address(value)
      return Match.new(found.server, "address", found.address) if found
    end
    nil
  end

  def by_service(resource, services)
    return unless resource.kind == "ip" && resource.data["service"]

    match = services[resource.data["service"]]
    Match.new(match.server, "service", nil) if match
  end

  def by_name(resource)
    return unless resource.kind.in?(%w[dedicated vps instance])

    [ resource.name, resource.data["reverse"], resource.external_id ].compact_blank.each do |name|
      server = @directory.by_host(name, names: true)
      return Match.new(server, "name", nil) if server
    end
    nil
  end
end
