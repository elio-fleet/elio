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

  test "serious fixable CVEs are on the overview and in the daily digest" do
    sign_in users(:viewer)
    get root_path
    assert_select "#attention li.attention-item[data-tone=crit]", text: /2 serveurs.*1 vulnérabilité grave corrigeable/m
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
