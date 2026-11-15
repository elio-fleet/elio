require "ipaddr"

# Listening ports of a server (ss) with the process and systemd unit behind
# each one, and the firewall state (ufw, otherwise firewalld, nftables or
# iptables) with the DOCKER-USER chain of Docker.
# Processes of other users and the firewall need root: without it the
# collection is partial. Elio never changes the firewall.
class Inventory::Collectors::Ports < Inventory::Collector
  # Ports of the usual ufw application profiles.
  UFW_APPS = { "OpenSSH" => [ "22/tcp" ], "Nginx HTTP" => [ "80/tcp" ], "Nginx HTTPS" => [ "443/tcp" ], "Nginx Full" => [ "80/tcp", "443/tcp" ],
               "Apache" => [ "80/tcp" ], "Apache Secure" => [ "443/tcp" ], "Apache Full" => [ "80/tcp", "443/tcp" ], "Postfix" => [ "25/tcp" ] }.freeze

  def collect
    result = run("inventory.ports")
    raise Error, I18n.t("inventory.collectors.ports.failed", exit_status: result.stderr.strip.presence || "code #{result.exit_status}") if result.stdout.blank?

    sections = self.class.sections(result.stdout)
    return unsupported(I18n.t("inventory.collectors.ports.no_ss")) if sections["ss"].to_s.strip == "unsupported"

    data = self.class.parse(sections)
    privileged? ? ok(data) : partial(data, I18n.t("inventory.collectors.ports.without_root"))
  end

  def self.parse(sections)
    units = parse_cgroups(sections["cgroups"].to_s)
    { "listening" => parse_ss(sections["ss"].to_s, units), "firewall" => parse_firewall(sections) }
  end

  # "tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=812,fd=3))"
  def self.parse_ss(text, units = {})
    text.lines.filter_map do |line|
      proto, _state, _recv, _send, local, _peer, *process = line.split
      next unless proto && local && %w[tcp udp].include?(proto)

      address, port = split_address(local)
      next unless port&.match?(/\A\d+\z/)

      name = process.join(" ")[/\(\("([^"]+)"/, 1]
      pid = process.join(" ")[/pid=(\d+)/, 1]
      { "proto" => proto, "address" => address, "port" => port.to_i, "scope" => scope(address),
        "process" => name, "pid" => pid&.to_i, "unit" => (units[pid] if pid) }.compact
    end.uniq { |entry| entry.values_at("proto", "address", "port") }.sort_by { |entry| [ entry["port"], entry["proto"], entry["address"] ] }
  end

  # "812 0::/system.slice/ssh.service" → { "812" => "ssh.service" }
  def self.parse_cgroups(text)
    text.lines.filter_map do |line|
      pid, cgroup = line.strip.split(" ", 2)
      unit = cgroup.to_s.split("/").reverse.find { |part| part.end_with?(".service", ".scope") }
      [ pid, unit ] if pid && unit
    end.to_h
  end

  # "0.0.0.0:22", "[::]:22", "*:22", "127.0.0.53%lo:53", "[::ffff:127.0.0.1]:6379"
  def self.split_address(local)
    address, _, port = local.rpartition(":")
    address = address.delete_prefix("[").delete_suffix("]").sub(/%.*\z/, "")
    address = address.delete_prefix("::ffff:") if address.start_with?("::ffff:") && address.count(".") == 3
    [ address, port ]
  end

  # public (every interface or a public address), private (LAN, VPN) or local (loopback).
  def self.scope(address) = Inventory::IpScope.of(address)

  UNREADABLE = /permission denied|need to be root|must be root|Operation not permitted|Authorization failed|NOT_AUTHORIZED/i

  # The firewall that filters the incoming traffic (ufw, else firewalld, else
  # nftables, else iptables), its allow rules ("family" ipv4 / ipv6, none for
  # both), "ipv6_open" when it filters IPv4 only, and the rules of Docker's
  # DOCKER-USER chain (published ports skip the other rules).
  def self.parse_firewall(sections)
    ufw = sections["ufw"].to_s
    firewalld = sections["firewalld"].to_s
    nft = sections["nft"].to_s
    iptables = sections["iptables"].to_s
    unreadable = ->(text) { text.match?(UNREADABLE) }
    present = ->(text) { !text.strip.start_with?("absent") && !unreadable.(text) }

    firewall = if ufw.match?(/^Status: active/)
      parse_ufw(ufw).merge(ipv6_open_in_ip6tables(sections["ip6tables"].to_s))
    elsif present.(firewalld) && firewalld.match?(/^\s+target:/)
      parse_firewalld(firewalld, sections["firewalld_services"].to_s)
    elsif present.(nft) && nft.include?("hook input")
      parse_nft(nft)
    elsif present.(iptables) && iptables.include?("-P INPUT")
      parse_iptables(iptables, sections["ip6tables"].to_s)
    elsif [ ufw, firewalld, nft, iptables ].any? { |text| unreadable.(text) }
      { "tool" => "unknown", "active" => nil }
    else
      { "tool" => (ufw.include?("inactive") ? "ufw" : "none"), "active" => false }
    end
    docker_user = parse_docker_user(sections["docker_user"].to_s)
    docker_user ? firewall.merge("docker_user" => docker_user) : firewall
  end

  # ufw status verbose: "Default: deny (incoming), …" then "To  Action  From"
  # rules; "(v6)" marks the IPv6 copy of a rule.
  def self.parse_ufw(text)
    default = text[/^Default:\s*(\w+) \(incoming\)/, 1]
    allowed = text.lines.flat_map do |line|
      match = line.match(/\A(?<to>.+?)\s+(?<action>ALLOW|LIMIT)(?: IN)?\s+(?<from>.+?)\s*\z/)
      next [] unless match && !match[:to].start_with?("To")

      ipv6 = match[:to].include?("(v6)") || match[:from].include?("(v6)") || match[:from].include?(":")
      to = match[:to].sub(/\s*\(v6\)\z/, "").strip
      from = match[:from].sub(/\s*\(v6\)\z/, "").strip
      targets = UFW_APPS.fetch(to) { [ to.split.first ] }
      targets.map { |target| { "rule" => target, "from" => (from == "Anywhere" ? nil : from), "family" => (ipv6 ? "ipv6" : "ipv4") }.compact }
    end
    { "tool" => "ufw", "active" => true, "default_incoming" => default, "allowed" => allowed.uniq }
  end

  # firewall-cmd --list-all of the default and active zones. A zone with
  # sources filters only them (its rules are "from" them). Services become
  # their ports (firewall-cmd --info-service, section firewalld_services);
  # one without ports keeps its name.
  def self.parse_firewalld(text, services_text)
    services = firewalld_blocks(services_text).to_h { |name, fields| [ name, fields["ports"].to_s.split ] }
    zones = firewalld_blocks(text)
    open = zones.any? { |_name, fields| fields["sources"].to_s.empty? && fields["target"].to_s.casecmp?("ACCEPT") }
    allowed = zones.flat_map do |_name, fields|
      sources = fields["sources"].to_s.split.presence || [ nil ]
      rules = fields["services"].to_s.split.flat_map { |service| services.fetch(service, []).presence || [ service ] } + fields["ports"].to_s.split
      rules.map { |rule| firewalld_rule(rule) }.product(sources).map { |rule, source| { "rule" => rule, "from" => source }.compact } +
        fields["rich"].filter_map { |line| firewalld_rich_rule(line, services) }
    end
    { "tool" => "firewalld", "active" => true, "default_incoming" => (open ? "allow" : "deny"), "allowed" => allowed.uniq }
  end

  # A line starting at column 0 ("public (active)", "ssh") opens a block of
  # indented "key: value" fields; indented "rule …" lines are rich rules.
  # → [[name, { key => value, "rich" => [lines] }]]
  def self.firewalld_blocks(text)
    text.lines.each_with_object([]) do |line, blocks|
      if line.match?(/\A\S/)
        blocks << [ line.split.first, { "rich" => [] } ]
      elsif blocks.any? && line.strip.start_with?("rule ")
        blocks.last.last["rich"] << line.strip
      elsif blocks.any? && (match = line.chomp.match(/\A\s+([\w -]+):(.*)\z/))
        blocks.last.last[match[1].strip] = match[2].strip
      end
    end
  end

  # "9000-9100/tcp" → "9000:9100/tcp" (the notation of the port verdicts).
  def self.firewalld_rule(rule) = rule.sub(%r{\A(\d+)-(\d+)/}, '\1:\2/')

  # rule family="ipv4" source address="10.0.0.0/8" port port="5432" protocol="tcp" accept
  # rule family="ipv6" source address="2001:db8::/32" service name="ssh" accept
  def self.firewalld_rich_rule(line, services)
    return unless line.end_with?("accept")

    rule = if (port = line[/port port="([^"]+)"/, 1])
      firewalld_rule("#{port}/#{line[/protocol="([^"]+)"/, 1] || "tcp"}")
    elsif (service = line[/service name="([^"]+)"/, 1])
      services.fetch(service, []).first || service
    end
    { "rule" => rule, "from" => line[/source address="([^"]+)"/, 1], "family" => line[/family="([^"]+)"/, 1] }.compact if rule
  end

  # An nftables input chain that accepts everything without any rule filters
  # nothing. Its table gives the family it filters: inet both, ip IPv4 only
  # (IPv6 is then open unless an ip6 or inet table drops it), ip6 IPv6 only.
  def self.parse_nft(text)
    input = text[/chain input \{.*?\n\s*\}/m].to_s
    policy = input[/policy (\w+);/, 1]
    rules = input.lines.count { |line| line.match?(/\b(accept|drop|reject)\b/) && !line.include?("policy") }
    return { "tool" => "none", "active" => false } if policy != "drop" && rules.zero?

    family = { "ip" => "ipv4", "ip6" => "ipv6" }[text[0, text.index(input)].scan(/^table (\w+) /).last&.first]
    allowed = input.scan(/(tcp|udp) dport (\{[^}]+\}|\d+(?:-\d+)?) .*?accept/).flat_map do |proto, ports|
      ports.delete("{} ").split(",").map { |port| { "rule" => "#{port.tr("-", ":")}/#{proto}", "family" => family }.compact }
    end
    ipv6_filtered = text.scan(/^table (?:ip6|inet) \S+ \{.*?^\}/m).any? { |table| table.match?(/hook input.*policy drop/) }
    { "tool" => "nftables", "active" => true, "default_incoming" => (policy == "drop" ? "deny" : policy), "allowed" => allowed.uniq,
      "ipv6_open" => (true if family == "ipv4" && !ipv6_filtered) }.compact
  end

  # "-P INPUT ACCEPT" without any "-A INPUT" rule (the Debian default)
  # filters nothing. The IPv6 rules (ip6tables -S INPUT) are read the same way.
  def self.parse_iptables(text, ip6tables = "")
    policy = text[/^-P INPUT (\w+)/, 1]
    return { "tool" => "none", "active" => false } if policy == "ACCEPT" && text.lines.none? { |line| line.start_with?("-A INPUT") }

    allowed = iptables_allowed(text, "ipv4") + iptables_allowed(ip6tables, "ipv6")
    { "tool" => "iptables", "active" => true, "default_incoming" => ({ "DROP" => "deny", "REJECT" => "deny" }[policy] || policy&.downcase), "allowed" => allowed.uniq }
      .merge(ipv6_open_in_ip6tables(ip6tables))
  end

  def self.iptables_allowed(text, family)
    text.lines.filter_map do |line|
      next unless line.include?("-j ACCEPT") && (port = line[/--dports? (\S+)/, 1])

      { "rule" => "#{port}/#{line[/-p (\w+)/, 1] || "tcp"}", "from" => line[/-s (\S+)/, 1], "family" => family }.compact
    end
  end

  # { "ipv6_open" => true } when ip6tables accepts everything without any
  # rule: the firewall filters IPv4 only (ufw with IPV6=no, iptables alone).
  def self.ipv6_open_in_ip6tables(text)
    open = text.match?(/^-P INPUT ACCEPT/) && text.lines.none? { |line| line.start_with?("-A INPUT") }
    open ? { "ipv6_open" => true } : {}
  end

  # iptables -S DOCKER-USER: Docker creates it with a single "-j RETURN"; any
  # other rule (a DROP, the jumps of ufw-docker) may filter the published
  # ports. nil without the chain (no Docker) or when it is not readable.
  def self.parse_docker_user(text)
    return unless text.include?("-N DOCKER-USER")

    text.lines.map(&:strip).select { |line| line.start_with?("-A DOCKER-USER ") && line != "-A DOCKER-USER -j RETURN" }
        .map { |line| line.delete_prefix("-A DOCKER-USER ") }.first(50)
  end

  # Public ports that appeared or disappeared (by port and protocol).
  def self.changes(previous, data)
    public_ports = ->(entries) { Array(entries).select { |entry| entry["scope"] == "public" }.map { |entry| "#{entry["port"]}/#{entry["proto"]}" }.to_set }
    processes = Array(data["listening"]).to_h { |entry| [ "#{entry["port"]}/#{entry["proto"]}", entry["process"] ] }
    before = public_ports.(previous["listening"])
    after = public_ports.(data["listening"])

    (after - before).sort.map { |port| { kind: :port_opened, data: { port: port, process: processes[port] }.compact } } +
      (before - after).sort.map { |port| { kind: :port_closed, data: { port: port } } }
  end
end
