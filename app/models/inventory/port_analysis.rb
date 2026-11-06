# What a server exposes, from its last inventory: the listening ports (ports
# category) merged with the ports published by Docker containers (services
# category, they may not show in ss), the firewall state, the ports expected
# by its groups, and the ufw rules to copy. Elio never applies them.
class Inventory::PortAnalysis
  # firewall: allowed (rule found), blocked (default deny, no rule), open (no
  # filtering firewall), docker (published by Docker, which bypasses ufw) or
  # unknown (firewall not readable).
  Port = Data.define(:port, :proto, :addresses, :scope, :process, :unit, :container, :firewall, :unexpected) do
    def key = "#{port}/#{proto}"
    def public? = scope == "public"
  end

  RULE = %r{\A(\d+(?:[:,]\d+)*)(?:/(tcp|udp))?\z}

  attr_reader :server, :firewall

  def initialize(server)
    @server = server
    @snapshot = server.inventory("ports")
    @firewall = @snapshot&.collected? ? (@snapshot.data["firewall"] || {}) : {}
  end

  def collected? = @snapshot&.collected? || false

  def snapshot = @snapshot

  def expected_ports
    @expected_ports ||= server.server_groups.filter_map(&:expected_port_list)
  end

  def ports
    @ports ||= begin
      entries = listening.group_by { |entry| [ entry["port"], entry["proto"] ] }
      published.each { |(port, proto), container| entries[[ port, proto ]] ||= [ { "port" => port, "proto" => proto, "address" => container[:address], "process" => "dockerd" } ] }
      entries.map { |(port, proto), group| build(port, proto, group, published[[ port, proto ]]) }
             .sort_by { |entry| [ { "public" => 0, "private" => 1, "local" => 2 }.fetch(entry.scope, 3), entry.port, entry.proto ] }
    end
  end

  def public_ports = ports.select(&:public?)

  def unexpected_ports = ports.select(&:unexpected)

  def firewall_active? = firewall["active"] == true

  def firewall_label
    case firewall["tool"]
    when "ufw", "nftables", "iptables"
      tool = { "ufw" => "ufw", "nftables" => "nftables", "iptables" => "iptables" }.fetch(firewall["tool"])
      firewall_active? ? I18n.t(firewall["default_incoming"] == "deny" ? "inventory.port_analysis.active_deny" : "inventory.port_analysis.active_allow", tool: tool) : I18n.t("inventory.port_analysis.inactive", tool: tool)
    when "none" then I18n.t("inventory.port_analysis.no_firewall")
    else I18n.t("inventory.port_analysis.unknown_firewall")
    end
  end

  # Commands to copy, SSH first so the session is not cut. With "block all
  # the incoming IPv6" (AppSetting#ufw_block_ipv6), the ports are allowed from
  # IPv4 only: the default policy then denies every IPv6 connection (an SSH
  # source in IPv6 stays allowed). Never IPV6=no in /etc/default/ufw: ufw
  # would stop managing IPv6 and leave it open.
  def suggested_ufw_rules(block_ipv6: AppSetting.current.ufw_block_ipv6)
    @block_ipv6 = block_ipv6
    ssh_port = server.port
    lines = [ I18n.t("inventory.port_analysis.header", server_name: server.name),
              *(I18n.t("inventory.port_analysis.ipv6_blocked") if block_ipv6),
              "sudo ufw default deny incoming", "sudo ufw default allow outgoing", *ssh_rules(ssh_port) ]
    public_ports.reject { |entry| entry.port == ssh_port && entry.proto == "tcp" }.each do |entry|
      label = comment_for(entry)
      lines << if entry.container
        I18n.t("inventory.port_analysis.docker", key: entry.key, container: entry.container)
      elsif entry.unexpected
        I18n.t("inventory.port_analysis.unexpected", key: entry.key, label: label)
      else
        allow_rule(entry.port, entry.proto, label)
      end
    end
    ports.select { |entry| entry.scope == "private" }.each do |entry|
      lines << I18n.t("inventory.port_analysis.private", key: entry.key, comment_for: (comment_for(entry)), addresses_join: (entry.addresses.join(", ")))
    end
    lines << "sudo ufw enable"
    lines.join("\n")
  end

  private

  def listening = collected? ? Array(@snapshot.data["listening"]) : []

  # { [port, proto] => { name:, address: } } from the containers' published ports.
  def published
    @published ||= begin
      services = server.inventory("services")
      containers = services&.collected? ? Array(services.data["containers"]) : []
      containers.each_with_object({}) do |container, result|
        next unless container["state"] == "running"

        container["ports"].to_s.scan(%r{(?:(\[?[\d.:a-f]*\]?):)?(\d+)->\d+/(tcp|udp)}).each do |address, port, proto|
          result[[ port.to_i, proto ]] ||= { name: container["name"], address: address.to_s.delete("[]").presence || "0.0.0.0" }
        end
      end
    end
  end

  def build(port, proto, group, container)
    addresses = group.map { |entry| entry["address"] }.uniq
    scopes = group.map { |entry| entry["scope"] || Inventory::Collectors::Ports.scope(entry["address"].to_s) }
    scope = %w[public private local].find { |candidate| scopes.include?(candidate) }
    main = group.find { |entry| entry["process"] } || group.first
    container_name = container&.fetch(:name)
    unexpected = scope == "public" && expected_ports.any? && expected_ports.none? { |list| list.include?(port, proto) }

    Port.new(port: port, proto: proto, addresses: addresses, scope: scope, process: main["process"], unit: main["unit"], container: container_name,
             firewall: (scope == "public" ? firewall_state(port, proto, container_name) : nil), unexpected: unexpected)
  end

  def firewall_state(port, proto, container)
    return "unknown" if firewall["active"].nil?
    return "open" unless firewall_active? && firewall["default_incoming"] == "deny"
    return "docker" if container

    rule_allows?(port, proto) ? "allowed" : "blocked"
  end

  def rule_allows?(port, proto)
    Array(firewall["allowed"]).any? do |rule|
      match = rule["rule"].to_s.match(RULE)
      next false unless match && (match[2].nil? || match[2] == proto)

      match[1].split(",").any? do |part|
        from, to = part.split(":").map(&:to_i)
        port.between?(from, to || from)
      end
    end
  end

  # SSH first: open to everyone, or only from the SSH sources of the server
  # (with a reminder that Elio's own address must be among them).
  def ssh_rules(ssh_port)
    sources = server.ssh_sources
    return [ allow_rule(ssh_port, "tcp", "ssh (Elio)") ] if sources.empty?

    [ I18n.t("inventory.port_analysis.ssh_sources", names: sources.map(&:name).join(", ")),
      I18n.t("inventory.port_analysis.ssh_sources_elio"),
      *sources.map { |source| "sudo ufw allow from #{source.cidr} to any port #{ssh_port} proto tcp comment 'ssh (#{source.comment_name})'" } ]
  end

  def allow_rule(port, proto, comment)
    return "sudo ufw allow #{port}/#{proto} comment '#{comment}'" unless @block_ipv6

    "sudo ufw allow from 0.0.0.0/0 to any port #{port} proto #{proto} comment '#{comment}'"
  end

  # Process or unit name, limited to safe characters for a ufw comment.
  def comment_for(entry)
    (entry.container || entry.unit&.delete_suffix(".service") || entry.process || I18n.t("inventory.port_analysis.port", port: entry.port)).gsub(/[^\w .@-]/, "").first(40)
  end
end
