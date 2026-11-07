require "test_helper"

class PackagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PackageHelpers

  setup do
    record_packages(servers(:web), [ { manager: "dpkg", name: "openssl", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true },
                                     { manager: "dpkg", name: "libssl3", version: "3.0.14", arch: "amd64" } ])
    record_packages(servers(:db), [ { manager: "dpkg", name: "openssl", version: "3.0.15", arch: "amd64" } ])
  end

  test "requires authentication" do
    get packages_path
    assert_redirected_to new_user_session_path
  end

  test "without a search, lists the security updates waiting on the fleet" do
    sign_in users(:viewer)

    get packages_path

    assert_select ".security-updates tr.security-update", 1 do
      assert_select "a[href=?]", packages_path(q: "openssl"), text: "openssl"
      assert_select "td", text: "3.0.15"
      assert_select "a[href=?]", server_path(servers(:web), tab: "packages"), text: "Web"
    end
    assert_select ".filter-bar span", text: "1 serveur n'a pas encore d'inventaire des paquets."
    assert_select "nav.main-nav a[aria-current=page][href=?]", packages_path
  end

  test "shows which servers have a package, by version" do
    sign_in users(:viewer)

    get packages_path(q: "ssl")

    assert_select ".package-result", 2
    assert_select ".package-result", text: /openssl/ do
      assert_select "span", text: "2 serveurs · 2 versions"
      assert_select "tr.package-version", 2
      assert_select "tr.package-version", text: /3\.0\.14.*→ 3\.0\.15.*sécurité.*Web/m
      assert_select "tr.package-version", text: /3\.0\.15.*à jour.*Database/m
    end
  end

  test "says when nothing matches" do
    sign_in users(:viewer)
    get packages_path(q: "zzz")
    assert_select "p", text: "Aucun paquet ne contient « zzz »."
  end
end
