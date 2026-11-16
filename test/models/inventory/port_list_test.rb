require "test_helper"

class Inventory::PortListTest < ActiveSupport::TestCase
  test "ports, ranges and protocols" do
    list = Inventory::PortList.new("22, 80;443/tcp  51820/udp 6000-6007/TCP")

    assert list.include?(22, "udp")
    assert list.include?(443, "tcp")
    assert_not list.include?(443, "udp")
    assert list.include?(51_820, "udp")
    assert list.include?(6003, "tcp")
    assert_not list.include?(8080, "tcp")
    assert_empty list.invalid
  end

  test "a default protocol for the items written without one, shown as they are checked" do
    list = Inventory::PortList.new("22, 8000-8100, 51820/udp", default_proto: "tcp")

    assert list.include?(22, "tcp")
    assert_not list.include?(22, "udp")
    assert list.include?(8050, "tcp")
    assert_not list.include?(8050, "udp")
    assert list.include?(51_820, "udp")
    assert_equal "22/tcp, 8000-8100/tcp, 51820/udp", list.to_s
    assert_equal "22, 8000-8100, 51820/udp", Inventory::PortList.new("22 8000:8100 51820/UDP", default_proto: "").to_s
  end

  test "keeps the invalid items" do
    assert_equal %w[http 70000 9-3], Inventory::PortList.new("22, http, 70000, 9-3").invalid
    assert Inventory::PortList.new("").empty?
  end

  test "server groups validate their expected ports" do
    group = server_groups(:production)

    assert group.update(expected_ports: " 22,  80 , 443/tcp ")
    assert_equal "22, 80 , 443/tcp", group.expected_ports
    assert group.expected_port_list.include?(80, "tcp")
    assert_not group.update(expected_ports: "22, ssh")
    assert_includes group.errors[:expected_ports].sole, "ssh"
    assert_nil server_groups(:staging).expected_port_list

    assert group.update(expected_ports: "22, 8000-8100", expected_ports_proto: "udp")
    assert_not group.expected_port_list.include?(8000, "tcp")
    assert group.update(expected_ports_proto: "")
    assert_nil group.expected_ports_proto
    assert group.expected_port_list.include?(8000, "tcp")
    assert_not group.update(expected_ports_proto: "icmp")
    assert_includes group.errors[:expected_ports_proto].sole, "n'est pas inclus"
  end
end
