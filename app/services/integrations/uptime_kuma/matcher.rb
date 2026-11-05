require "resolv"

# Finds the server a probe watches, by the rules enabled in the extension:
# its host name when it is one of the server's IPs (WireGuard included), the
# host of its URL (also resolved in DNS, optionally), or the server's name in
# the probe's name ("[SRV] FR-UTILS-1"). A manual link always wins. With the
# Technitium DNS extension, a host name is also looked up in its records.
class Integrations::UptimeKuma::Matcher
  Match = Data.define(:server, :matched_by, :address)

  DNS_TIMEOUT = 2

  def initialize(servers, manual_links: {}, by_ip: true, by_host: true, resolve_dns: false, by_name: true)
    @directory = ServerDirectory.new(servers)
    @servers_by_id = @directory.servers.index_by(&:id)
    @manual_links = manual_links
    @rules = { by_ip:, by_host:, resolve_dns:, by_name: }
    @dns = {}
    # { "web.example.com" => server } from the Technitium records attached to a server.
    @dns_names = Integration.enabled?("technitium") ? TechnitiumRecord.attached.pluck(:name, :server_id).to_h { |name, id| [ name, @servers_by_id[id] ] }.compact : {}
  end

  # Match or nil (no server).
  def call(monitor)
    if @manual_links.key?(monitor.id.to_s)
      server = @servers_by_id[@manual_links[monitor.id.to_s]]
      return server ? Match.new(server, "manual", nil) : nil
    end

    by_target(monitor.hostname) || by_target(url_host(monitor.url)) || by_monitor_name(monitor.name)
  end

  private

  def by_target(host)
    return if host.blank?

    if Inventory::IpScope.ip?(host)
      found = @directory.by_address(host) if @rules[:by_ip]
      return found && Match.new(found.server, "ip", host)
    end
    return unless @rules[:by_host]

    server = @directory.by_host(host)
    return Match.new(server, "url", nil) if server

    server = @dns_names[host.downcase.chomp(".")]
    return Match.new(server, "technitium", nil) if server
    return unless @rules[:resolve_dns]

    resolve(host).each do |address|
      found = @directory.by_address(address)
      return Match.new(found.server, "dns", address) if found
    end
    nil
  end

  def by_monitor_name(name)
    server = @directory.named_in(name) if @rules[:by_name]
    Match.new(server, "name", nil) if server
  end

  def url_host(url)
    URI.parse(url.to_s).host&.delete_prefix("[")&.delete_suffix("]")
  rescue URI::InvalidURIError
    nil
  end

  def resolve(host)
    @dns[host] ||= Resolv::DNS.open do |dns|
      dns.timeouts = DNS_TIMEOUT
      dns.getaddresses(host).map(&:to_s)
    end
  rescue Resolv::ResolvError, SocketError, SystemCallError
    @dns[host] = []
  end
end
