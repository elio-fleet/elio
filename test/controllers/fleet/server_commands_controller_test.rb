require "test_helper"

class ServerCommandsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @server = servers(:web) }

  def record_os(data) = @server.inventory_snapshots.create!(category: "os", status: "ok", data: data, checked_at: Time.current, collected_at: Time.current)

  test "requires authentication" do
    get server_commands_path(@server)
    assert_redirected_to new_user_session_path
  end

  test "returns 404 for an unknown server" do
    sign_in users(:viewer)
    get server_commands_path(server_id: 0)
    assert_response :not_found
  end

  test "lists every command of config/ssh_commands.yml, by role, and marks only the ones that write" do
    sign_in users(:viewer)
    get server_commands_path(@server)

    assert_response :success
    assert_select "h1", "Commandes lancées par Elio"
    Ssh::Commands.all.each_value.group_by(&:role).each do |role, commands|
      assert_select "#commands-#{role} .server-command", commands.size
    end
    Ssh::Commands.all.each_value do |command|
      assert_select "#command-#{command.key.tr(".", "-")}[data-writes=?]", command.writes?.to_s do
        assert_select "code", command.key
        assert_select ".command-writes", command.writes? ? 1 : 0
      end
    end
    assert_select ".command-writes", minimum: 1
    assert_select "#commands-keys .command-writes", css_select(".command-writes").size
  end

  test "a command registered later appears without touching the page" do
    sign_in users(:viewer)
    Ssh::Commands.extra = { "inventory" => { "new_probe" => { "description" => "A new probe.", "default" => "cat /etc/new-probe" } } }

    get server_commands_path(@server)

    assert_select "#command-inventory-new_probe" do
      assert_select "p", text: "A new probe."
      assert_select ".command-template", "cat /etc/new-probe"
    end
  ensure
    Ssh::Commands.extra = nil
  end

  test "shows the variant of the server's distribution family" do
    sign_in users(:viewer)
    record_os("id" => "ubuntu", "id_like" => "debian", "name" => "Ubuntu 24.04")

    get server_commands_path(@server)

    assert_select ".page-subtitle", text: /ubuntu, debian/
    assert_select "#command-inventory-health" do
      assert_select ".command-template", text: /apt-get -s/
      assert_select "span", text: "Variante : debian"
    end
  end

  test "shows the default variants until the distribution is known" do
    sign_in users(:viewer)
    get server_commands_path(@server)

    assert_select ".page-subtitle", text: /Distribution encore inconnue/
    health = Ssh::Commands.fetch("inventory.health")
    assert_select "#command-inventory-health .command-template", health.variants.fetch("default").strip
  end

  test "says when root commands go through sudo" do
    sign_in users(:viewer)
    @server.update_column(:privilege, "sudo")
    get server_commands_path(@server)
    assert_select "#command-keys-read_accounts", text: /Précédée de sudo -n/

    @server.update_column(:privilege, "root")
    get server_commands_path(@server)
    assert_select "#command-keys-read_accounts", text: /sudo -n/, count: 0
  end
end
