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

  test "shows where each package comes from, filters the ones outside the distribution, links to the fleet comparison" do
    record_packages(servers(:web), [
      { manager: "dpkg", name: "curl", version: "7.88", arch: "amd64", origin: "Debian/bookworm-security" },
      { manager: "dpkg", name: "linux-image-amd64", version: "6.10", arch: "amd64", origin: "Debian Backports/bookworm-backports" },
      { manager: "dpkg", name: "docker-ce", version: "27.3", arch: "amd64", origin: "Docker/bookworm" },
      { manager: "dpkg", name: "elio-tool", version: "1.0", arch: "amd64", origin: "local" },
      { manager: "snap", name: "lxd", version: "5.21" }
    ])
    sign_in users(:viewer)

    get server_packages_path(servers(:web))
    assert_select "tr.package", text: /curl/ do
      assert_select "a[href=?][target=_top]", packages_path(q: "curl"), text: "curl"
      assert_select "td.package-origin span:not(.badge)", "Debian/bookworm-security"
    end
    assert_select "tr.package", text: /docker-ce/ do
      assert_select "td.package-origin .badge", "Docker/bookworm"
    end
    assert_select "tr.package", text: /elio-tool/ do
      assert_select "td.package-origin .badge.text-warn-ink", "Hors dépôt"
    end

    get server_packages_path(servers(:web), outside: "1")
    assert_equal %w[docker-ce elio-tool linux-image-amd64], css_select("tr.package td:first-child a").map(&:text)
  end

  test "the last dpkg.log changes, under the list" do
    snapshot = servers(:web).inventory("packages")
    snapshot.update!(data: snapshot.data.merge("history" => [
      { "at" => "2024-09-10 14:02:11", "action" => "upgrade", "name" => "curl", "from" => "7.88.1-10+deb12u6", "to" => "7.88.1-10+deb12u7" },
      { "at" => "2024-09-02 06:25:13", "action" => "install", "name" => "htop", "from" => nil, "to" => "3.2.2" }
    ]))
    sign_in users(:viewer)

    get server_packages_path(servers(:web))

    assert_select "details.package-history summary", "2 derniers changements (dpkg.log)"
    assert_select "tr.package-change", 2
    assert_select "tr.package-change:first-child", text: /2024-09-10 14:02:11\s+Mis à jour\s+curl\s+7\.88\.1-10\+deb12u6 → 7\.88\.1-10\+deb12u7/
    assert_select "tr.package-change:last-child td:last-child", "3.2.2"
  end
end
