require "test_helper"

class ServerPartialCollectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def record(server, category, message)
    server.inventory_snapshots.where(category: category).delete_all
    server.inventory_snapshots.create!(category: category, status: "partial", message: message, data: {}, collected_at: Time.current, checked_at: Time.current)
  end

  test "the overview tells a cause shared by several categories once, with the categories and how to get a full collection" do
    server = servers(:web)
    server.update_columns(privilege: "none")
    docker = I18n.t("inventory.collector.no_docker_access")
    %w[packages services docker].each { |category| record(server, category, docker) }
    record(server, "ports", I18n.t("inventory.collectors.ports.without_root"))
    sign_in users(:viewer)

    get server_path(server)

    assert_select "#partial-collection" do
      assert_select "h2", text: "Collecte partielle"
      assert_select ".partial-cause", 2
      assert_select ".partial-cause:first-child", text: /Pas d'accès à Docker.*Concerne : Paquets, Services, Docker/m do
        assert_select "a[href=?]", server_path(server, tab: "packages")
        assert_select "a[href=?]", server_path(server, tab: "docker")
      end
      assert_select ".partial-cause:last-child a[href=?]", server_path(server, tab: "firewall")
      assert_select ".partial-fix", text: /sudo sans mot de passe \(NOPASSWD.*groupe docker suffit.*ligne sudoers limitée/m do
        assert_select "a[href=?]", server_commands_path(server)
      end
    end
  end

  test "with root access, a partial collection gives no root advice; without any, no panel" do
    server = servers(:web)
    server.update_columns(privilege: "sudo")
    sign_in users(:viewer)

    get server_path(server)
    assert_select "#partial-collection", 0

    record(server, "docker", "Vulnérabilités de 1 image illisibles : timeout")
    get server_path(server)
    assert_select "#partial-collection .partial-cause", text: /Vulnérabilités de 1 image illisibles/
    assert_select "#partial-collection .partial-fix", 0
  end

  test "the Partial badge of a tab links to the explanation" do
    server = servers(:web)
    record(server, "ports", I18n.t("inventory.collectors.ports.without_root"))
    sign_in users(:viewer)

    get server_path(server, tab: "firewall")

    assert_select "a.partial-collection-link[href=?] .inventory-status", server_path(server, anchor: "partial-collection"), text: "Partiel"
  end
end
