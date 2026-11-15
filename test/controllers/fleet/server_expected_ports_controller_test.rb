require "test_helper"

class ServerExpectedPortsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  setup do
    @server = servers(:db) # in group Production
    @server.update_columns(port: 22, ssh_ok: true)
    server_groups(:production).update!(expected_ports: "22, 6432")
    record_ports(@server)
    @server.refresh_health!
  end

  test "an operator ignores an unexpected port: added to the server's expected ports, logged, health recomputed" do
    assert_equal [ "Port 9100/tcp inattendu" ], @server.health_reason_texts
    sign_in users(:operator)

    get server_path(@server, tab: "firewall")
    assert_select "#server-firewall-ports tr.firewall-port[data-port='9100/tcp'] form[action=?] button.ignore-port", server_expected_port_path(@server), text: "Ignorer"

    post server_expected_port_path(@server), params: { port: 9100, proto: "tcp" }

    assert_redirected_to server_path(@server, tab: "firewall")
    assert_equal "9100/tcp est désormais attendu sur « #{@server.name} » : il n'est plus signalé.", flash[:notice]
    assert_equal "9100/tcp", @server.reload.expected_ports
    assert_equal "22, 6432", server_groups(:production).reload.expected_ports
    activity = Activity.of_kind(:server_updated).sole
    assert_equal [ @server, users(:operator), %w[expected_ports], "9100/tcp" ], [ activity.server, activity.user, activity.data["changed"], activity.data["port"] ]
    assert_empty @server.health_reason_texts

    follow_redirect!
    assert_select ".port-unexpected", 0
    assert_select ".ports-summary", text: /Ports attendus : 22, 6432 · 9100\/tcp/

    assert_no_difference -> { Activity.count } do
      post server_expected_port_path(@server), params: { port: 9100, proto: "tcp" }
    end
    assert_equal "9100/tcp", @server.reload.expected_ports
  end

  test "an invalid port or protocol changes nothing" do
    sign_in users(:operator)

    post server_expected_port_path(@server), params: { port: 9100, proto: "icmp" }
    post server_expected_port_path(@server), params: { port: 70_000, proto: "tcp" }

    assert_equal "Port invalide.", flash[:alert]
    assert_nil @server.reload.expected_ports
    assert_equal 0, Activity.of_kind(:server_updated).count
  end

  test "a viewer sees the unexpected port without the button" do
    sign_in users(:viewer)
    get server_path(@server, tab: "firewall")
    assert_select ".port-unexpected"
    assert_select "button.ignore-port", 0
  end
end
