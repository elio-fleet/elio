require "application_system_test_case"

class VulnerabilitiesSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include ScoreHelpers

  setup do
    vulnerable(servers(:web), "CVE-2024-6387")
    vulnerable(servers(:web), "CVE-2024-0002", severity: "low", fixed: nil)
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 8.1, version: "3.1", vector: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", data: { "description" => "regreSSHion" } } ])
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
    CveRating.refresh!
    sign_in users(:viewer)
  end

  test "a click on a CVE of the server opens its detail in a modal, closed with Escape" do
    visit server_path(servers(:web), tab: "vulnerabilities", view: "cves")

    within("tr.server-vulnerability[data-cve='CVE-2024-6387']") do
      assert_selector ".cve-score", text: "8,1"
      assert_selector ".cve-exploited", text: "exploitée"
    end
    find("tr.server-vulnerability[data-cve='CVE-2024-6387']").click # the CVE link covers the whole row

    within("dialog.vulnerability-dialog[open]") do
      assert_selector ".vulnerability-detail[data-cve='CVE-2024-6387']"
      assert_text "regreSSHion"
      assert_text "Vecteur : réseau"
      assert_selector ".detail-on-server", text: /sur web/i # uppercase heading
    end
    find("body").send_keys(:escape)
    assert_no_selector "dialog.vulnerability-dialog[open]"

    find("a.vulnerability-link", text: "CVE-2024-0002").click
    assert_selector "dialog.vulnerability-dialog[open] .vulnerability-detail[data-cve='CVE-2024-0002']"
    assert_selector "li.detail-provider-score[data-provider=nvd] .provider-pending", text: "pas encore demandé"
  end

  test "on the Docker CVE tab, the packages of an image load when it is unfolded, and a CVE opens its detail" do
    servers(:web).server_vulnerabilities.create!(origin: "image", image: "nginx:1.27", source: "debian", cve: "CVE-2024-6387", source_package: "openssh",
                                                 packages: %w[openssh-client], installed_version: "1:9.2p1-2", fixed_version: "1:9.2p1-2+deb12u3", severity: "high")
    visit docker_path(tab: "cves")

    within("section.image-vulnerabilities[data-image='nginx:1.27']") do
      assert_no_selector "li.vulnerability-package"
      find("details > summary").click
      assert_selector "li.vulnerability-package[data-package='openssh@nginx:1.27']"
      click_on "CVE-2024-6387"
    end
    assert_selector "dialog.vulnerability-dialog[open] .vulnerability-detail[data-cve='CVE-2024-6387']"
  end
end
