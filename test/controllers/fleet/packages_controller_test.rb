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

  test "compares a package across servers: exact name first, newest dpkg version first, with its repositories" do
    record_packages(servers(:web), [ { manager: "dpkg", name: "curl", version: "7.88.1-10+deb12u10", arch: "amd64", origin: "Debian/bookworm-security" },
                                     { manager: "dpkg", name: "libcurl4", version: "7.88.1-10+deb12u10", arch: "amd64" } ])
    record_packages(servers(:db), [ { manager: "dpkg", name: "curl", version: "7.88.1-10+deb12u9", arch: "amd64", origin: "Debian/bookworm" },
                                    { manager: "dpkg", name: "acurl", version: "1", arch: "amd64" } ])
    sign_in users(:viewer)

    get packages_path(q: "curl")

    assert_equal %w[curl acurl libcurl4], css_select(".package-result h2").map { |heading| heading.text.split.first }
    versions = css_select(".package-result").first.css("tr.package-version")
    assert_equal [ "7.88.1-10+deb12u10", "7.88.1-10+deb12u9" ], versions.map { |row| row.at_css("td").text.strip }
    assert_equal [ "Debian/bookworm-security", "Debian/bookworm" ], versions.map { |row| row.at_css("td.package-origin").text.strip }
  end

  test "by server: each server's security updates and the apt command that installs them all" do
    record_packages(servers(:web), [ { manager: "dpkg", name: "openssl", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true },
                                     { manager: "dpkg", name: "linux-image-6.1.0-28-amd64", version: "6.1.119-1", arch: "amd64", available_version: "6.1.123-1",
                                       security: true, origin: "Debian/bookworm-security" },
                                     { manager: "dpkg", name: "vim", version: "9.0", arch: "amd64", available_version: "9.1" } ])
    record_packages(servers(:backup), [ { manager: "dpkg", name: "libssl3", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true } ])
    sign_in users(:viewer)

    get packages_path(view: "servers")

    assert_select ".view-toggle a[aria-pressed=true]", text: "Par serveur"
    assert_equal %w[Backup Web], css_select(".server-updates h2 a").map { |link| link.text.strip }
    assert_select ".server-updates[data-server=?]", servers(:web).id.to_s do
      assert_select "pre.update-command", text: "sudo apt-get install --only-upgrade linux-image-6.1.0-28-amd64 openssl"
      assert_select "tr.server-update", 2
      assert_select "h2 .reboot-needed", text: "redémarrage"
      assert_select "tr.server-update", text: /linux-image.*redémarrage.*6\.1\.119-1.*6\.1\.123-1.*Debian\/bookworm-security/m
      assert_select "p", text: /ne s'applique qu'après un redémarrage/
    end
    assert_select ".server-updates[data-server=?]", servers(:backup).id.to_s do
      assert_select "pre.update-command", text: "apt-get install --only-upgrade libssl3"
      assert_select ".reboot-needed", 0
    end
    assert_select ".server-updates[data-server=?]", servers(:db).id.to_s, 0
  end

  test "by server: says when no security update waits" do
    record_packages(servers(:web), [ { manager: "dpkg", name: "openssl", version: "3.0.15", arch: "amd64" } ])
    sign_in users(:viewer)

    get packages_path(view: "servers")

    assert_select ".server-updates", 0
    assert_select "p", text: "Aucune mise à jour de sécurité en attente."
  end

  test "by server: the number of queries does not grow with the servers" do
    sign_in users(:viewer)
    count = -> do
      ActiveRecord::Base.connection.clear_query_cache
      queries = 0
      ActiveSupport::Notifications.subscribed(->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }, "sql.active_record") { get packages_path(view: "servers") }
      queries
    end
    count.call # warm up
    before = count.call
    record_packages(servers(:backup), [ { manager: "dpkg", name: "libssl3", version: "3.0.14", arch: "amd64", available_version: "3.0.15", security: true } ])
    record_packages(servers(:db), [ { manager: "dpkg", name: "curl", version: "1", arch: "amd64", available_version: "2", security: true } ])

    assert_equal before, count.call
    assert_select ".server-updates", 3
  end

  test "by package: flags the updates that need a reboot" do
    record_packages(servers(:db), [ { manager: "dpkg", name: "intel-microcode", version: "1", arch: "amd64", available_version: "2", security: true } ])
    sign_in users(:viewer)

    get packages_path

    assert_select "tr.security-update", text: /intel-microcode/ do
      assert_select ".reboot-needed", text: "redémarrage"
    end
    assert_select "tr.security-update", text: /openssl/ do
      assert_select ".reboot-needed", 0
    end
  end

  test "exports the security updates of the fleet as CSV, one line per server and package" do
    record_packages(servers(:db), [ { manager: "dpkg", name: "linux-image-amd64", version: "1", arch: "amd64", available_version: "2", security: true,
                                      origin: "=cmd" } ])
    sign_in users(:viewer)

    get packages_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="elio-security-updates-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
    rows = CSV.parse(response.body)
    assert_equal %w[server package installed_version available_version origin reboot], rows.first
    assert_equal [ [ "Database", "linux-image-amd64", "1", "2", "'=cmd", "true" ], [ "Web", "openssl", "3.0.14", "3.0.15", nil, "false" ] ], rows.drop(1)
  end
end
