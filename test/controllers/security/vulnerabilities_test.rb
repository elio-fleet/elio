require "test_helper"

class VulnerabilitiesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include VulnerabilityHelpers
  include PackageHelpers

  setup do
    record_os(servers(:web))
    record_os(servers(:db))
    load_debian_feed
    record_packages(servers(:web), [ dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"), dpkg("libssl3", "3.0.14-1~deb12u1", source: "openssl") ])
    record_packages(servers(:db), [ dpkg("openssh-server", "1:9.2p1-2+deb12u2", source: "openssh"), dpkg("nginx", "1.22.1-9") ])
    [ servers(:web), servers(:db) ].each(&:refresh_health!)
  end

  test "the server tab lists the CVEs, fixable and most serious first, with filters" do
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves")

    assert_select "nav.server-tabs a[data-tab=vulnerabilities][aria-current=page]", text: /Vulnérabilités\s*3/
    assert_select "#server-vulnerabilities" do
      assert_select ".vulnerabilities-summary", text: /4 vulnérabilités connues\s+· 3 corrigeables/
      assert_select "tr.server-vulnerability", 4
      assert_select "tr.server-vulnerability:first-child[data-cve=CVE-2024-6387][data-fixable=true]", text: /Haute.*openssh.*1:9.2p1-2\+deb12u2 →\s+1:9.2p1-2\+deb12u3/m
      assert_select "tr.server-vulnerability:last-child[data-cve=CVE-2023-51767]", text: /pas de correctif/
      assert_select "tr.server-vulnerability a.vulnerability-link[href=?][data-turbo-frame=vulnerability-detail][data-action='modal#open']",
                    vulnerability_path("CVE-2024-6387", server_id: servers(:web).id)
      assert_select "dialog.vulnerability-dialog turbo-frame#vulnerability-detail"
      assert_select "th", text: "Description", count: 0
      assert_select "tr.server-vulnerability[data-cve=CVE-2024-9143] td[title='libssl3']", "openssl", "the source package only, binaries in the title and the modal"
    end

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves", fixable: "1", severity: "high")
    assert_select "tr.server-vulnerability", 1
  end

  test "the tab explains an uncovered distribution or a feed never downloaded" do
    record_os(servers(:web), id: "alpine", version_id: "3.20")
    sign_in users(:one)
    get server_path(servers(:web), tab: "vulnerabilities", view: "cves")
    assert_select "#server-vulnerabilities tr.server-vulnerability", 4, "rows of the previous match stay until the next one"

    servers(:web).server_vulnerabilities.delete_all
    get server_path(servers(:web), tab: "vulnerabilities", view: "cves")
    assert_select ".vulnerabilities-empty", /Distribution non couverte/

    record_os(servers(:web), id: "ubuntu", codename: "noble", version_id: "24.04")
    get server_path(servers(:web), tab: "vulnerabilities", view: "cves")
    assert_select ".vulnerabilities-empty", /La base Ubuntu \(OSV\) n'a pas encore été téléchargée/
    assert_select ".vulnerabilities-empty a[href=?]", settings_vulnerabilities_path
  end

  test "the fleet page groups by CVE, with the servers touched and the filters" do
    sign_in users(:viewer)

    get vulnerabilities_path(view: "cves")
    assert_response :success
    assert_select "nav.main-nav a[aria-current=page][href=?]", vulnerabilities_path
    assert_select "#stat-cves .stat-value", "5"
    assert_select "#stat-serious .stat-value", "1"
    assert_select "#stat-affected .stat-value", "2"
    assert_select "tr.fleet-vulnerability:first-child[data-cve=CVE-2024-6387]", text: /Haute.*openssh.*2 ·\s+Database, Web.*corrigeable/m
    assert_select "tr.fleet-vulnerability[data-cve=CVE-2023-44487]", text: /nginx.*1 ·\s+Database.*pas de correctif/m

    get vulnerabilities_path(q: "openssl")
    assert_select "tr.fleet-vulnerability", 2
    get vulnerabilities_path(fixable: "1", severity: "high")
    assert_select "tr.fleet-vulnerability", 1
    get vulnerabilities_path(q: "CVE-2099")
    assert_select "p", text: "Aucune vulnérabilité ne correspond."
  end

  test "the page: tiles that filter, the CVE page has a breadcrumb back to the list" do
    sign_in users(:viewer)
    get vulnerabilities_path
    assert_select "a#stat-serious[href=?]", vulnerabilities_path(fixable: 1, severity: "high")
    assert_select "a#stat-cves[aria-current=true]"
    get vulnerabilities_path(fixable: 1, severity: "high")
    assert_select "a#stat-serious[aria-current=true]"

    cve = ServerVulnerability.first.cve
    get vulnerability_path(cve)
    assert_select "nav.breadcrumbs a[href=?]", vulnerabilities_path
    assert_select "nav.breadcrumbs span[aria-current=page]", cve
  end

  test "serious fixable CVEs are on the overview and in the daily digest" do
    sign_in users(:viewer)
    get root_path
    assert_select "#attention li.attention-item[data-tone=crit]", text: /1 vulnérabilité grave corrigeable.*Database.*Web/m
    assert_select "#attention a[href=?]", vulnerabilities_path(fixable: 1, severity: "high", origin: "host")

    assert_includes NotificationDigest.new.lines, "Vulnérabilités : 5 connue(s), 3 corrigeable(s) dont 1 grave(s), sur 2 serveurs."
  end

  test "the fleet list shows the CVE as the first health reason" do
    sign_in users(:viewer)
    get servers_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} .server-notes", text: /Vulnérabilité CVE-2024-6387 corrigeable/
  end

  test "by package (the default): one line per package with the update, the command, its worst CVEs" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "vulnerabilities")

    assert_select ".vulnerability-view-toggle a[data-view=packages][aria-pressed=true]"
    assert_select ".package-summary", /2 paquets à mettre à jour\s+corrigeraient 3 CVE/
    assert_select "li.vulnerability-package", 2
    assert_select "li.vulnerability-package:first-child[data-package=openssh][data-state=pending]" do
      assert_select ".package-name", "openssh"
      assert_select ".package-cves", /2 CVE/
      assert_select ".package-update", /1:9.2p1-2\+deb12u2 → 1:9.2p1-2\+deb12u3.*pas encore dans les dépôts.*corrige 1.*1 sans correctif/m
      assert_select ".package-details .package-cve", 2
      assert_select ".package-details a.vulnerability-link[data-turbo-frame=vulnerability-detail]", 2
    end
    assert_select "dialog.vulnerability-dialog"

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves", package: "openssh")
    assert_select ".package-filter", /openssh/
    assert_select "tr.server-vulnerability", 2
    get server_path(servers(:web), tab: "vulnerabilities")
    assert_select ".vulnerability-view-toggle a[data-view=cves][aria-pressed=true]", 1, "the choice is remembered"
  end

  test "the fleet page by package lists the servers touched" do
    sign_in users(:viewer)
    get vulnerabilities_path(view: "packages")

    assert_select "li.vulnerability-package[data-package=openssh]" do
      assert_select ".package-name", "openssh"
      assert_select "summary", /2 serveurs/
      assert_select ".package-servers a", 2
      assert_select ".package-command", 0
    end
  end

  test "the fleet page filters on a server, combined with the group" do
    sign_in users(:viewer)

    get vulnerabilities_path(view: "cves", server: servers(:db).id)
    assert_select "select[name=server] option[selected]", "Database"
    assert_select "tr.fleet-vulnerability", 3
    assert_select "tr.fleet-vulnerability[data-cve=CVE-2024-9143]", 0, "openssl is only on Web"
    assert_select "#stat-affected .stat-value", "1"
    assert_select "a#stat-fixable[href=?]", vulnerabilities_path(server: servers(:db).id, view: "cves", fixable: 1)

    get vulnerabilities_path(view: "cves", group: server_groups(:production).id, server: servers(:db).id)
    assert_select "tr.fleet-vulnerability", 3
    assert_select "select[name=server] option", 3, "all servers + the two of the group"

    get vulnerabilities_path(view: "cves", group: server_groups(:staging).id, server: servers(:db).id)
    assert_select "select[name=server] option[selected]", 0, "a server outside the group is dropped"
    assert_select "p", text: "Aucune vulnérabilité ne correspond."
  end

  test "the fleet page filters on the exploited CVEs (KEV) and on a minimum EPSS" do
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
    CveScore.store("epss", [ { cve: "CVE-2024-6387", score: 0.42, data: { "percentile" => 0.99 } },
                             { cve: "CVE-2023-44487", score: 0.95, data: { "percentile" => 0.999 } },
                             { cve: "CVE-2024-9143", score: 0.002, data: { "percentile" => 0.3 } } ])
    CveRating.refresh!
    sign_in users(:viewer)

    get vulnerabilities_path(view: "cves", exploited: 1)
    assert_select "input[type=checkbox][name=exploited][checked]"
    assert_select "tr.fleet-vulnerability", 1
    assert_select "tr.fleet-vulnerability[data-cve=CVE-2024-6387]"

    get vulnerabilities_path(view: "cves", epss: "10")
    assert_select "select[name=epss] option[selected]", /EPSS ≥ 10[[:space:]]%/
    assert_equal %w[CVE-2024-6387 CVE-2023-44487].sort, css_select("tr.fleet-vulnerability").map { |row| row["data-cve"] }.sort
    get vulnerabilities_path(view: "packages", epss: "50")
    assert_select "li.vulnerability-package", 1
    assert_select "li.vulnerability-package[data-package=nginx]"
    get vulnerabilities_path(view: "cves", epss: "50", exploited: 1)
    assert_select "tr.fleet-vulnerability", 0
    get vulnerabilities_path(view: "cves", epss: "33")
    assert_select "tr.fleet-vulnerability", 5, "an unknown threshold is ignored"
  end

  test "a package that holds most of the CVEs is pointed out" do
    sign_in users(:viewer)

    get vulnerabilities_path
    assert_select ".vulnerability-concentration", 0, "openssh holds 2 of 5 CVEs: not most of them"

    get vulnerabilities_path(server: servers(:db).id)
    assert_select ".vulnerability-concentration[data-package=openssh]", text: /openssh concentre à lui seul 67[[:space:]]% de ces CVE \(2 sur 3\)/
    get vulnerabilities_path(server: servers(:db).id, view: "cves")
    assert_select ".vulnerability-concentration[data-package=openssh]"

    get vulnerabilities_path(q: "openssh")
    assert_select ".vulnerability-concentration", 0, "a single package is not a concentration"
  end

  test "the fleet page exports its filtered rows in CSV and JSON, for every role that sees it" do
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
    CveRating.refresh!
    sign_in users(:viewer)

    get vulnerabilities_path(view: "cves")
    assert_select ".actions-menu a.export-csv[href=?][data-turbo=false]", vulnerabilities_path(format: :csv)
    assert_select ".actions-menu a.export-json[href=?]", vulnerabilities_path(format: :json)
    assert_select ".actions-menu form[action=?]", refresh_settings_vulnerabilities_path, 0, "the admin actions stay hidden"
    get vulnerabilities_path(severity: "high", page: 2)
    assert_select ".actions-menu a.export-csv[href=?]", vulnerabilities_path(severity: "high", format: :csv)

    get vulnerabilities_path(format: :csv, server: servers(:db).id)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="elio-vulnerabilities-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
    csv = CSV.parse(response.body, headers: true)
    assert_equal %w[server origin image cve severity score epss exploited source_package packages installed_version fixed_version fixable], csv.headers
    assert_equal [ "Database" ], csv.map { |row| row["server"] }.uniq
    row = csv.find { |line| line["cve"] == "CVE-2024-6387" }
    assert_equal [ "host", "high", "true", "openssh", "openssh-server", "1:9.2p1-2+deb12u2", "1:9.2p1-2+deb12u3", "true" ],
                 row.fields(*%w[origin severity exploited source_package packages installed_version fixed_version fixable])

    get vulnerabilities_path(format: :json, exploited: 1)
    json = response.parsed_body
    assert_equal({ "origin" => "host", "exploited" => true }, json["filters"])
    assert_equal 2, json["count"]
    assert_equal [ "Database", "Web" ], json["vulnerabilities"].map { |line| line["server"] }
    assert_equal [ "CVE-2024-6387" ], json["vulnerabilities"].map { |line| line["cve"] }.uniq
  end

  test "the server tab searches a CVE or a package (source or installed binary), in both views" do
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "vulnerabilities", view: "packages", q: "libssl")
    assert_select "input.vulnerability-search[value=libssl]"
    assert_select "li.vulnerability-package", 1
    assert_select "li.vulnerability-package[data-package=openssl] details[open]"

    get server_path(servers(:web), tab: "vulnerabilities", view: "packages", q: "cve-2024-6387")
    assert_select "li.vulnerability-package[data-package=openssh]", 1
    assert_select "li.vulnerability-package .package-cve", 1

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves", q: "openss")
    assert_select "tr.server-vulnerability", 4
    assert_select ".vulnerability-view-toggle a[data-view=packages][href*='q=openss']"

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves", q: "zzz")
    assert_select ".vulnerabilities-none", "Aucune CVE ni paquet ne correspond à « zzz »."
    get server_path(servers(:web), tab: "vulnerabilities", view: "packages", q: "zzz")
    assert_select ".vulnerabilities-none", "Aucune CVE ni paquet ne correspond à « zzz »."
  end
end
