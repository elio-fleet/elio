require "test_helper"

class ServerPackagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PackageHelpers

  setup do
    record_packages(servers(:web), [
      { manager: "dpkg", name: "openssl", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true },
      { manager: "dpkg", name: "curl", version: "7.88", arch: "amd64", available_version: "7.89", security: false },
      { manager: "dpkg", name: "libssl3", version: "3.0.14", arch: "i386" },
      { manager: "docker", name: "nginx", version: "1.27" }
    ])
  end

  test "requires authentication" do
    get server_packages_path(servers(:web))
    assert_redirected_to new_user_session_path
  end

  test "the server page lazy-loads the packages" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "packages")
    assert_select "#server-packages turbo-frame[loading=lazy][src=?]", server_packages_path(servers(:web))
  end

  test "lists the packages with their updates and the counts" do
    sign_in users(:viewer)

    get server_packages_path(servers(:web))

    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(servers(:web), :packages)}" do
      assert_select "strong", "4"
      assert_select "span", text: /2 à mettre à jour,\s+dont 1 de sécurité/
      assert_select "tr.package", 4
      assert_select "tr.package:first-child td", text: /\Acurl/m
      assert_select "tr.package", text: /openssl.*→ 3\.0\.15\s+sécurité/m
      assert_select "tr.package td", text: /libssl3\s*i386/
      # The search reloads only the results: the field keeps its focus.
      assert_select "form.packages-filters[data-turbo-frame=?]", ActionView::RecordIdentifier.dom_id(servers(:web), :package_results)
      assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(servers(:web), :package_results)} tr.package"
    end
  end

  test "searches, filters by type and by updates" do
    sign_in users(:viewer)

    get server_packages_path(servers(:web), q: "SSL")
    assert_select "tr.package", 2

    get server_packages_path(servers(:web), manager: "docker")
    assert_select "tr.package td", text: "nginx"
    assert_select "tr.package", 1

    get server_packages_path(servers(:web), updates: "1")
    assert_select "tr.package", 2
    assert_select "tr.package:first-child td", text: /\Aopenssl/m

    get server_packages_path(servers(:web), q: "zzz")
    assert_select "p", text: "Aucun paquet ne correspond."
  end

  test "without inventory, or on an unsupported system" do
    sign_in users(:viewer)
    get server_packages_path(servers(:db))
    assert_select ".packages-empty", "Pas encore d'inventaire des paquets."

    servers(:db).inventory_snapshots.create!(category: "packages", status: "unsupported", message: "Ni dpkg ni snap sur ce système", checked_at: Time.current, collected_at: Time.current)
    get server_packages_path(servers(:db))
    assert_select ".packages-empty", "Ni dpkg ni snap sur ce système"
  end
end
