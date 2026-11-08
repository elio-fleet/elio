require "test_helper"

class ServerNetworkTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def record_network(server)
    sections = Inventory::Collector.sections(file_fixture("inventory/network/debian13-wireguard.txt").read)
    data = Inventory::Collectors::Network.parse(sections)
    server.inventory_snapshots.create!(category: "network", status: "ok", data: data, collected_at: Time.current, checked_at: Time.current)
    server.update_columns(Inventory::Collectors::Network.server_attributes(data))
  end

  setup { sign_in users(:one) }

  test "the overview tab shows the interfaces, a VPN highlighted, the scope as an icon, and the addresses added by hand" do
    record_network(servers(:web))
    servers(:web).update!(extra_addresses_text: "203.0.113.4")

    get server_path(servers(:web))

    assert_select "#server-network" do
      assert_select "tr.network-address", 4
      assert_select "tr.network-address[data-interface=wg0] .interface-kind[data-kind=wireguard]", text: "VPN"
      assert_select "tr.network-address[data-interface=wg0] .interface-kind[title*=WireGuard]"
      assert_select "tr.network-address", text: /WireGuard/, count: 0
      assert_select "tr.network-address[data-interface=wg0]", text: %r{10\.8\.0\.48/24}
      assert_select "tr.network-address[data-interface=ens18] .address-scope[data-scope=public][title^=Publique] svg"
      assert_select "tr.network-address[data-interface=ens18] .address-scope .sr-only", text: "publique"
      assert_select "tr.network-address[data-interface=wg0] .address-scope[data-scope=private]", text: "privée"
      assert_select "tr.network-address .badge.address-scope", 0
      assert_select ".extra-addresses", text: /203\.0\.113\.4/
    end
  end

  test "without a network inventory" do
    get server_path(servers(:web))
    assert_select "#server-network", text: /Pas encore d'inventaire du réseau/
  end

  test "the header and the fleet show the host name when it differs" do
    servers(:web).inventory_snapshots.create!(category: "os", status: "ok", data: { "hostname" => "fr-prod-web-1.example.internal" },
                                               collected_at: Time.current, checked_at: Time.current)
    get server_path(servers(:web))
    assert_select ".server-summary", text: /fr-prod-web-1\.example\.internal/

    get servers_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .server-hostname", "fr-prod-web-1.example.internal"
  end

  test "the fleet can be searched by address, keeping the other filters" do
    record_network(servers(:web))

    get servers_path(q: "10.8.0.48")
    assert_select "#servers tbody tr", 1
    assert_select "#servers tbody tr", text: /Web/
    assert_select "input.fleet-search[value='10.8.0.48']"

    get servers_path(q: "nothing-like-this")
    assert_select "#servers", 0
    assert_select "p", text: "Aucun serveur ne correspond à ces filtres."
  end

  test "addresses can be added by hand in the form" do
    get edit_server_path(servers(:web))
    assert_select "input[name='server[extra_addresses_text]']"

    patch server_path(servers(:web)), params: { server: { extra_addresses_text: "203.0.113.4 2001:db8::4" } }
    assert_equal [ "203.0.113.4", "2001:db8::4" ], servers(:web).reload.extra_addresses

    patch server_path(servers(:web)), params: { server: { extra_addresses_text: "pas-une-ip" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", text: /pas-une-ip/
  end
end
