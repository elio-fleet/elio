require "test_helper"

class Integrations::Ovh::FirewallTest < ActiveSupport::TestCase
  RULES = [
    { "sequence" => 19, "action" => "deny", "protocol" => "ipv4" },
    { "sequence" => 0, "action" => "permit", "protocol" => "tcp", "destinationPort" => "eq 22", "source" => "192.0.2.0/24" },
    { "sequence" => 1, "action" => "permit", "protocol" => "tcp", "destinationPort" => "range 8000 8080" },
    { "sequence" => 2, "action" => "permit", "protocol" => "udp", "destinationPort" => "eq 51820" }
  ].freeze

  def verdict(proto, port, firewall = { "enabled" => true, "rules" => RULES }) = Integrations::Ovh::Firewall.verdict(firewall, proto, port)

  test "first matching rule in sequence order" do
    assert_equal :restricted, verdict("tcp", 22)
    assert_equal :permit, verdict("tcp", 8000)
    assert_equal :permit, verdict("udp", 51820)
    assert_equal :deny, verdict("tcp", 3306), "the final deny ipv4"
    assert_equal :deny, verdict("udp", 22)
  end

  test "no rule matching lets through; a disabled firewall says nothing" do
    assert_equal :permit, verdict("tcp", 3306, { "enabled" => true, "rules" => RULES.first(3).drop(1) })
    assert_nil verdict("tcp", 22, { "enabled" => false, "rules" => RULES })
    assert_nil verdict("tcp", 22, nil)
  end

  test "an IPv6 address is not covered: the OVH network firewall filters only IPv4" do
    assert_equal :not_covered, Integrations::Ovh::Firewall.verdict({ "enabled" => true, "rules" => RULES }, "tcp", 22, ip: "2001:db8::10")
    assert_equal :not_covered, Integrations::Ovh::Firewall.verdict(nil, "tcp", 22, ip: "2001:db8::/64")
    assert_equal :deny, Integrations::Ovh::Firewall.verdict({ "enabled" => true, "rules" => RULES }, "tcp", 3306, ip: "203.0.113.10")
  end
end
