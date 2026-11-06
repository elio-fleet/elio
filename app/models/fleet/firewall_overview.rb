# Everything that filters the traffic to a server, from what Elio knows: its
# own firewall (ports inventory, Inventory::PortAnalysis) and, with the
# OVHcloud extension, the network firewall of its OVH IPs. The Firewall tab of
# the server page and the firewall prompt (ServerPrompt#firewall) read it.
class FirewallOverview
  # One OVH network firewall: the IP it filters, in the block, and its state.
  OvhFirewall = Data.define(:block, :ip, :enabled, :rules, :data) do
    def sorted_rules = rules.sort_by { |rule| rule["sequence"].to_i }
  end

  attr_reader :server, :analysis

  def initialize(server)
    @server = server
    @analysis = Inventory::PortAnalysis.new(server)
  end

  def ovh? = Integration.enabled?(:ovh)

  # The OVH IP blocks of the server (empty without the extension).
  def ovh_blocks
    @ovh_blocks ||= ovh? ? server.ovh_resources.where(kind: "ip").order(:name).to_a : []
  end

  def ovh_firewalls
    @ovh_firewalls ||= ovh_blocks.flat_map do |block|
      (block.data["firewall"] || {}).map do |ip, firewall|
        OvhFirewall.new(block: block.name, ip: ip, enabled: firewall["enabled"] == true, rules: Array(firewall["rules"]), data: firewall)
      end
    end
  end

  # [[ip, { "permanent" =>, "state" => }]] of the anti-DDoS of the OVH IPs.
  def mitigations = ovh_blocks.flat_map { |block| Array(block.data["mitigation"]) }

  # OVH blocks whose firewall was not read (rights missing on the API key).
  def unread_ovh_blocks = ovh_blocks.reject { |block| block.data.key?("firewall") }

  # :permit, :deny, :restricted, :not_covered (IPv6), or nil when that firewall is off.
  def ovh_verdict(firewall, port) = Integrations::Ovh::Firewall.verdict(firewall.data, port.proto, port.port, ip: firewall.ip)

  # The public IPv6 addresses of the server (temporary ones included: they are reachable too).
  def public_ipv6
    @public_ipv6 ||= server.addresses.select { |address| ipv6?(address) && Inventory::IpScope.of(address) == "public" }
  end

  # Public ports that listen on IPv6 (all interfaces, or one of its IPv6 addresses).
  def ipv6_ports
    return [] if public_ipv6.empty?

    analysis.public_ports.select { |port| port.addresses.any? { |address| address.in?([ "::", "*", "[::]" ]) || public_ipv6.include?(address.delete("[]")) } }
  end

  # The OVH network firewall filters only IPv4: these ports skip it.
  def ipv6_bypassing_ovh = ovh_blocks.any? ? ipv6_ports : []

  def anything? = analysis.collected? || ovh_blocks.any?

  private

  def ipv6?(address)
    IPAddr.new(address.to_s).ipv6?
  rescue IPAddr::Error
    false
  end
end
