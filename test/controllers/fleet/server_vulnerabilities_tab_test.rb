require "test_helper"

# The Vulnerabilities tab of a server: by package unless the CVE view was
# chosen, and a kernel already updated but not running yet shown as waiting
# for a reboot (not as an update to install).
class ServerVulnerabilitiesTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PackageHelpers
  include VulnerabilityHelpers

  def kernel_cve(cve, fixed:, severity: "high")
    @server.server_vulnerabilities.create!(origin: "host", source: "debian", cve: cve, source_package: "linux", packages: [ "linux-image-6.12.107+deb13-amd64" ],
                                           installed_version: "6.12.107-1", fixed_version: fixed, severity: severity, distro_severity: severity)
  end

  setup do
    @server = servers(:web)
    record_os(@server)
    VulnerabilityFeed.for("debian").update!(refreshed_at: Time.current)
    sign_in users(:viewer)
  end

  test "by package by default; the toggle is remembered, opening the CVEs of one package is not" do
    kernel_cve("CVE-2026-0001", fixed: "6.12.113-1")

    get server_path(@server, tab: "vulnerabilities")
    assert_select ".vulnerability-view-toggle a[data-view=packages][aria-pressed=true]"
    assert_select "li.vulnerability-package[data-package=linux]"

    get server_path(@server, tab: "vulnerabilities", view: "cves")
    assert_equal "cves", cookies[:elio_vulnerability_view]
    get server_path(@server, tab: "vulnerabilities", view: "packages")
    assert_equal "packages", cookies[:elio_vulnerability_view]

    get server_path(@server, tab: "vulnerabilities", view: "cves", package: "linux")
    assert_select "tr.server-vulnerability[data-cve=CVE-2026-0001]"
    assert_equal "packages", cookies[:elio_vulnerability_view], "a drill-down into one package keeps the chosen view"
    get server_path(@server, tab: "vulnerabilities")
    assert_select ".vulnerability-view-toggle a[data-view=packages][aria-pressed=true]"
  end

  test "the fixed kernel installed but not running: a reboot, not an update to install" do
    record_packages(@server, [ dpkg("linux-image-6.12.107+deb13-amd64", "6.12.107-1", source: "linux-signed-amd64", source_version: "6.12.107+1"),
                               dpkg("linux-image-6.12.113+deb13-amd64", "6.12.113-1", source: "linux-signed-amd64", source_version: "6.12.113+1") ])
    kernel_cve("CVE-2026-0001", fixed: "6.12.111-1", severity: "critical")
    kernel_cve("CVE-2026-0002", fixed: "6.12.113-1")

    get server_path(@server, tab: "vulnerabilities", view: "packages")
    assert_select "li.vulnerability-package[data-package=linux][data-state=reboot]" do
      assert_select ".update-state", "installé, redémarrage nécessaire"
      assert_select ".package-reboot", /Le noyau 6.12.113-1 est déjà installé, mais le serveur tourne encore sur 6.12.107-1/
      assert_select ".package-command", 0
    end
    assert_select "details.fix-plan" do
      assert_select ".fix-plan-system", 0, "nothing to install"
      assert_select "li.fix-step[data-kind=reboot]", /Redémarrer sur le noyau 6.12.113-1/
      assert_select "li.fix-step[data-kind=reboot] .fix-commands", 0, "Elio never hands out a reboot to paste"
      assert_select ".fix-plan-reboot"
    end

    get vulnerability_path("CVE-2026-0001", server_id: @server.id)
    assert_select ".fix-plan[data-state=reboot]", /redémarrage nécessaire/
    assert_select ".fix-plan[data-state=reboot] .fix-commands", 0
  end
end
