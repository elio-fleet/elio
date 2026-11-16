require "resolv"

# Finds the server a probe watches, by the rules enabled in the extension:
# its tag naming the server ("server: vm-db1", Uptime Kuma 2.x only), its
# host name when it is one of the server's IPs (WireGuard included), the
# host of its URL (also resolved in DNS, optionally), or the server's name in
# the probe's name ("[SRV] FR-UTILS-1"). A manual link always wins. With the
# DNS of the fleet (OVHcloud, Technitium extensions), a host name is also
# looked up in its records. #explain tells why a probe matches no server.
class Integrations::UptimeKuma::Matcher
  Match = Data.define(:server, :matched_by, :address)

  DNS_TIMEOUT = 2

  # Uptime Kuma keeps only these characters of a tag in /metrics ("vm-db1" → "vmdb1").
  def self.tag_key(text) = text.to_s.gsub(/[^a-zA-Z0-9_]/, "").downcase

  def initialize(servers, manual_links: {}, tag: nil, by_ip: true, by_host: true, resolve_dns: false, by_name: true)
    @directory = ServerDirectory.new(servers)
    @servers_by_id = @directory.servers.index_by(&:id)
    @manual_links = manual_links
    @tag = self.class.tag_key(tag).presence
    @servers_by_tag_key = @directory.servers.index_by { |server| self.class.tag_key(server.name) }
    @rules = { by_ip:, by_host:, resolve_dns:, by_name: }
    @dns = {}
    # { "web.example.com" => server } from the DNS records attached to a server (every source).
    @dns_names = DnsRecord.attached.pluck(:name, :server_id).to_h { |name, id| [ name, @servers_by_id[id] ] }.compact
  end

  # Match or nil (no server).
  def call(monitor)
    if @manual_links.key?(monitor.id.to_s)
      server = @servers_by_id[@manual_links[monitor.id.to_s]]
      return server ? Match.new(server, "manual", nil) : nil
    end

    by_tag(monitor.tags) || by_target(monitor.hostname) || by_target(url_host(monitor.url)) || by_monitor_name(monitor.name)
  end

  # Why #call finds no server for this probe, about its first clue (manual
  # link, tag, then target): { "key" => …, "params" => {…} } (labels:
  # uptime_kuma_monitor.unmatched.*). DNS answers are those of #call.
  def explain(monitor)
    return reason("manual_none") if @manual_links.key?(monitor.id.to_s)

    values = tag_values(monitor.tags)
    return reason("unknown_tag", tag: values.join(", ")) if values.any?

    host = monitor.hostname.presence || url_host(monitor.url).presence
    return reason(@rules[:by_name] ? "no_target" : "no_target_name_off") if host.nil?
    return reason(@rules[:by_ip] ? "unknown_ip" : "ip_off", address: host) if Inventory::IpScope.ip?(host)
    return reason("host_off", host:) unless @rules[:by_host]
    return reason("host_no_dns", host:) unless @rules[:resolve_dns]

    addresses = resolve(host)
    addresses.any? ? reason("resolved_elsewhere", host:, addresses: addresses.first(3).join(", ")) : reason("not_resolved", host:)
  end

  private

  def reason(key, **params) = { "key" => key, "params" => params.stringify_keys }

  # The values of the probe's tag named like the setting ("server:vmdb1";
  # Uptime Kuma joins several values with commas).
  def tag_values(tags)
    return [] unless @tag

    Array(tags).flat_map do |tag|
      name, value = tag.to_s.split(":", 2)
      self.class.tag_key(name) == @tag ? value.to_s.split(",").map(&:strip).compact_blank : []
    end
  end

  # A value names the server (its name in Elio or its host name, even
  # without the characters Uptime Kuma drops), or is one of its addresses.
  def by_tag(tags)
    tag_values(tags).each do |value|
      server = @directory.by_host(value, names: true) || @directory.by_address(value)&.server || @servers_by_tag_key[self.class.tag_key(value)]
      return Match.new(server, "tag", nil) if server
    end
    nil
  end

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
    return Match.new(server, "dns_record", nil) if server
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
