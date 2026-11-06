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

  # :permit, :deny, :restricted, or nil when that firewall is off.
  def ovh_verdict(firewall, port) = Integrations::Ovh::Firewall.verdict(firewall.data, port.proto, port.port)

  def anything? = analysis.collected? || ovh_blocks.any?
end
