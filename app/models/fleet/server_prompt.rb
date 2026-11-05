# Texts to paste into an AI assistant, generated from what Elio knows about a
# server (its last inventory): which Uptime Kuma monitors to create, which
# rules to set in the OVHcloud network firewall. In the reader's language.
# Never anything secret: no key, token, password or API credential, only
# names, addresses, ports and versions.
#
#   ServerPrompt.new(server).monitors
#   ServerPrompt.new(server).ovh_firewall
class ServerPrompt
  def initialize(server)
    @server = server
  end

  def monitors
    document(:monitors, [
      server_section, addresses_section, dns_names_section, services_section, containers_section, ports_section,
      section(:existing_monitors, @server.uptime_kuma_monitors.order(:name).map { |monitor| monitor_line(monitor) })
    ])
  end

  def ovh_firewall
    document(:ovh_firewall, [
      server_section, addresses_section, dns_names_section, ports_section(public_only: true), local_firewall_section, ovh_firewall_section
    ])
  end

  private

  def t(key, **options) = I18n.t("server_prompt.#{key}", **options)

  def document(kind, sections)
    [ t("#{kind}.intro"), *sections.compact, "## #{t("task")}\n#{t("#{kind}.task", ssh_port: @server.port)}" ].join("\n\n")
  end

  # "## Title\n- line\n- line", or "(none)" under the title when empty.
  def section(key, lines)
    "## #{t("sections.#{key}")}\n" + (lines.any? ? lines.map { |line| "- #{line}" }.join("\n") : t("none"))
  end

  def os = @server.inventory("os")&.data || {}

  def server_section
    groups = @server.server_groups.map { |group| [ group.name, (t("expected_ports", ports: group.expected_ports) if group.expected_ports.present?) ].compact.join(" ") }
    section(:server, [
      t("fields.name", value: @server.name),
      (t("fields.hostname", value: os["hostname"]) if os["hostname"].present?),
      (t("fields.system", value: [ os["name"], os["kernel"] ].compact.join(", ")) if os["name"]),
      (t("fields.virtualization", value: os["virtualization"]) if os["virtualization"].present?),
      t("fields.ssh", value: "#{@server.host}:#{@server.port}"),
      (t("fields.groups", value: groups.join(" ; ")) if groups.any?)
    ].compact)
  end

  def addresses_section
    collected = Array(@server.inventory("network")&.data&.dig("addresses")).reject { |address| address["temporary"] }
    lines = collected.map do |address|
      details = [ address["family"], t("scopes.#{address["scope"]}", default: address["scope"].to_s), address["interface"], (address["kind"] unless address["kind"].in?([ nil, "ethernet" ])) ]
      "#{address["address"]}#{"/#{address["prefix"]}" if address["prefix"]} (#{details.compact.join(", ")})"
    end
    lines += Array(@server.extra_addresses).map { |address| "#{address} (#{t("manual_address")})" }
    section(:addresses, lines)
  end

  # The DNS names that point to the server (OVHcloud, Technitium…), with their source.
  def dns_names_section
    records = @server.dns_records.order(:name, :record_type, :source).to_a
    return if records.empty? && !DnsRecord.exists?

    section(:dns_names, records.map { |record| "#{record.name} (#{record.record_type} #{record.value}, #{record.source_label})" })
  end

  def services = @server.inventory("services")&.data || {}

  def services_section
    units = Array(services["units"]).select { |unit| unit["active"] == "active" }.sort_by { |unit| unit["name"] }
    section(:services, units.map { |unit| [ unit["name"], unit["description"] ].compact.join(" — ") })
  end

  def containers_section
    containers = Array(services["containers"])
    return if containers.empty? && services["docker"].nil?

    section(:containers, containers.sort_by { |container| container["name"].to_s }.map do |container|
      [ container["name"], t("container", image: container["image"], state: container["state"]),
        (t("published", ports: container["ports"]) if container["ports"]), (t("compose", project: container["project"]) if container["project"]) ].compact.join(", ")
    end)
  end

  def ports_section(public_only: false)
    analysis = Inventory::PortAnalysis.new(@server)
    return section(:ports, []).sub(t("none"), t("no_ports_inventory")) unless analysis.collected?

    ports = public_only ? analysis.public_ports : analysis.ports
    section(public_only ? :public_ports : :ports, ports.map do |port|
      what = [ port.process, (port.unit if port.unit && port.unit != port.process), (t("in_container", container: port.container) if port.container) ].compact.uniq.join(", ")
      [ "#{port.key} #{t("on", addresses: port.addresses.join(", "))} (#{t("scopes.#{port.scope}", default: port.scope)})",
        (what.presence && "— #{what}"), ("[#{t("unexpected")}]" if port.unexpected), ("[#{t("local_firewall.#{port.firewall}", default: port.firewall.to_s)}]" if public_only && port.firewall) ].compact.join(" ")
    end)
  end

  def local_firewall_section
    analysis = Inventory::PortAnalysis.new(@server)
    firewall = analysis.firewall
    lines = [ analysis.firewall_label ]
    lines += Array(firewall["allowed"]).map { |rule| t("allowed_rule", rule: rule["rule"], from: rule["from"] || t("anywhere")) }
    section(:local_firewall, lines)
  end

  def ovh_firewall_section
    blocks = @server.ovh_resources.where(kind: "ip").order(:name).to_a
    lines = blocks.flat_map do |block|
      firewalls = block.data["firewall"]
      next [ t("ovh.not_read", block: block.name) ] if firewalls.nil?
      next [ t("ovh.none", block: block.name) ] if firewalls.empty?

      firewalls.flat_map do |ip, firewall|
        rules = Array(firewall["rules"]).sort_by { |rule| rule["sequence"].to_i }
        [ t(firewall["enabled"] ? "ovh.enabled" : "ovh.disabled", ip: ip, count: rules.size),
          *rules.map { |rule| "  #{t("ovh.rule", sequence: rule["sequence"], action: rule["action"], protocol: rule["protocol"] || "any", port: rule["destinationPort"] || "*", source: rule["source"] || "any", option: [ rule["tcpOption"], rule["fragments"] && "fragments" ].compact.join(" "))}".rstrip } ]
      end
    end
    section(:ovh_firewall, lines)
  end

  def monitor_line(monitor)
    [ monitor.name, "(#{[ monitor.monitor_type, monitor.target ].compact.join(", ")})", "— #{monitor.state}" ].join(" ")
  end
end
