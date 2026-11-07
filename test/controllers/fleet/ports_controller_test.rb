require "test_helper"

class PortsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  setup do
    record_ports(servers(:db))
    record_ports(servers(:web), firewall: { "tool" => "none", "active" => false })
  end

  test "requires authentication" do
    get ports_path
    assert_redirected_to new_user_session_path
  end

  test "lists the public ports of the fleet, unfiltered ones first" do
    sign_in users(:viewer)

    get ports_path

    assert_select "#public-ports tr.public-port", 6
    assert_select "#public-ports tr.public-port:first-child", text: /Web.*non filtré/m
    assert_select "#public-ports a[href=?]", server_path(servers(:db), tab: "firewall")
    assert_select "p", text: /Sans inventaire des ports : Backup/
    assert_select "nav.main-nav a[aria-current=page][href=?]", ports_path
  end

  test "filters by port and by group, unexpected ports first" do
    server_groups(:production).update!(expected_ports: "22")
    sign_in users(:viewer)

    get ports_path(q: "9100")
    assert_select "#public-ports tr.public-port", 2
    assert_select "#public-ports .port-unexpected", 2

    get ports_path(group: server_groups(:staging).id)
    assert_select "p", text: "Aucun port public connu."

    get ports_path(q: "1")
    assert_select "p", text: "Aucun serveur n'expose le port 1."
  end
end
