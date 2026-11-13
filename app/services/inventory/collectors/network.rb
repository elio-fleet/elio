require "json"

# Network of a server: every interface with its addresses (IPv4 / IPv6,
# prefix, public / private / local) and its kind (ethernet, WireGuard,
# bridge, VLAN, tunnel…), from `ip -j` (iproute2), read-only, without root.
# Loopback and link-local addresses, and the interfaces of containers
# (Docker bridges, the host side of veth pairs) are left out: they say
# nothing about how to reach the server. Inside a container (an LXC on
# Proxmox), eth0 is itself a veth: it is the server's network card, kept as
# ethernet. The addresses feed the matching of external resources
# (Uptime Kuma probes, OVH IPs) with the servers.
class Inventory::Collectors::Network < Inventory::Collector
  KINDS = %w[wireguard ethernet wifi bridge vlan bond tun tap tunnel vxlan other].freeze # labels: inventory.network_kinds.*
  VPN_KINDS = %w[wireguard tun tap tunnel].freeze
  CONTAINER_INTERFACE = /\A(docker\d*|br-[0-9a-f]{12}|veth|cni|flannel|cali|vethwe|lxcbr|virbr)/

  def collect
    result = run("inventory.network")
    raise Error, I18n.t("inventory.collectors.network.failed", exit_status: (result.stderr.strip.presence || "code #{result.exit_status}")) if result.stdout.blank?

    sections = self.class.sections(result.stdout)
    return unsupported(I18n.t("inventory.collectors.network.no_ip")) if sections["addr"].to_s.strip == "unsupported"

    ok(self.class.parse(sections))
  rescue JSON::ParserError
    raise Error, I18n.t("inventory.collectors.network.unreadable")
  end

  def self.parse(sections)
    kinds = parse_links(sections["link"].to_s)
    interfaces = JSON.parse(sections["addr"].to_s.presence || "[]").filter_map do |entry|
      name = entry["ifname"].to_s
      kind = kinds[name] || kind_from_link_type(entry["link_type"])
      next if entry["link_type"] == "loopback" || name.match?(CONTAINER_INTERFACE)

      kind = "ethernet" if kind == "veth"

      addresses = Array(entry["addr_info"]).filter_map do |info|
        next unless %w[inet inet6].include?(info["family"]) && info["local"]
        next if info["scope"] == "link" || info["scope"] == "host"

        { "address" => info["local"], "family" => info["family"] == "inet" ? "ipv4" : "ipv6", "prefix" => info["prefixlen"],
          "scope" => Inventory::IpScope.of(info["local"]), "temporary" => (true if info["temporary"]) }.compact
      end
      { "name" => name, "kind" => kind, "state" => entry["operstate"], "mac" => entry["address"].presence,
        "up" => Array(entry["flags"]).include?("UP"), "addresses" => addresses }.compact
    end
    { "interfaces" => interfaces, "addresses" => interfaces.flat_map { |interface| interface["addresses"].map { |address| address.merge("interface" => interface["name"], "kind" => interface["kind"]) } } }
  end

  # ifname => kind, from `ip -d -j link` (linkinfo.info_kind).
  def self.parse_links(text)
    JSON.parse(text.presence || "[]").to_h do |entry|
      info_kind = entry.dig("linkinfo", "info_kind")
      kind = case info_kind
      when nil then kind_from_link_type(entry["link_type"], wireless: entry["ifname"].to_s.start_with?("wl"))
      when "wireguard", "bridge", "vlan", "bond", "veth", "vxlan" then info_kind
      when "tun" then entry.dig("linkinfo", "info_data", "type") == "tap" ? "tap" : "tun"
      when "ipip", "gre", "sit", "ip6tnl", "gretap" then "tunnel"
      else "other"
      end
      [ entry["ifname"].to_s, kind ]
    end
  rescue JSON::ParserError
    {}
  end

  def self.kind_from_link_type(link_type, wireless: false)
    case link_type
    when "ether" then wireless ? "wifi" : "ethernet"
    when "none" then "tunnel"
    else "other"
    end
  end

  # Summary kept on the server for matching: every address, public ones first.
  def self.server_attributes(data)
    addresses = Array(data["addresses"]).sort_by { |address| [ address["scope"] == "public" ? 0 : 1, address["family"] == "ipv4" ? 0 : 1 ] }
    { ip_addresses: addresses.map { |address| address["address"] }.uniq }
  end

  # Public addresses that appeared or disappeared (temporary IPv6 privacy addresses aside).
  def self.changes(previous, data)
    public_addresses = ->(entries) { Array(entries).select { |address| address["scope"] == "public" && !address["temporary"] }.map { |address| address["address"] }.to_set }
    before = public_addresses.(previous["addresses"])
    after = public_addresses.(data["addresses"])

    (after - before).sort.map { |address| { kind: :ip_address_added, data: { address: address } } } +
      (before - after).sort.map { |address| { kind: :ip_address_removed, data: { address: address } } }
  end
end
