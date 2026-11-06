# Evaluates the OVHcloud network firewall of an IP for a port, like OVH does:
# the rules in sequence order, the first one that matches decides; no
# matching rule lets the traffic through.
module Integrations::Ovh::Firewall
  # :permit, :deny or :restricted (allowed only from some sources); nil when
  # the firewall is off; :not_covered for an IPv6 address (the OVH network
  # firewall filters only IPv4).
  def self.verdict(firewall, proto, port, ip: nil)
    return :not_covered if ip && ipv6?(ip)
    return unless firewall && firewall["enabled"]

    rule = Array(firewall["rules"]).sort_by { |candidate| candidate["sequence"].to_i }.find { |candidate| matches?(candidate, proto, port) }
    return :permit unless rule
    return :deny if rule["action"] == "deny"

    rule["source"].present? && !%w[0.0.0.0/0 any].include?(rule["source"]) ? :restricted : :permit
  end

  def self.ipv6?(ip)
    IPAddr.new(ip.to_s.split("/").first).ipv6?
  rescue IPAddr::Error
    false
  end

  def self.matches?(rule, proto, port)
    protocol = rule["protocol"].to_s
    return false unless protocol.in?([ "", "ipv4", proto.to_s ])
    return true if rule["destinationPort"].blank? || protocol.in?(%w[ipv4 icmp])

    port_matches?(rule["destinationPort"].to_s, port.to_i)
  end
  private_class_method :matches?

  # "eq 22", "range 80 443" ("80 to 443"), "gt 1024", "lt 1024", "neq 25", or a bare number.
  def self.port_matches?(expression, port)
    numbers = expression.scan(/\d+/).map(&:to_i)
    case expression
    when /\Aneq/ then numbers.first != port
    when /\Agt/ then port > numbers.first.to_i
    when /\Alt/ then port < numbers.first.to_i
    when /range|to/ then port.between?(numbers.first.to_i, numbers.last.to_i)
    else numbers.first == port
    end
  end
  private_class_method :port_matches?
end
