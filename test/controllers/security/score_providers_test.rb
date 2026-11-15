require "test_helper"

class ScoreProvidersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include ScoreHelpers

  setup { sign_in users(:one) }

  test "the settings list the providers in order with their coverage, error and test" do
    CveScore.store("redhat", [ { cve: "CVE-2024-6387", score: 8.1 } ])
    provider("nvd").update!(last_error: "HTTP 503")

    get settings_vulnerabilities_path

    assert_select "#score-providers li.score-provider", 5
    assert_select "#score-providers li.score-provider:first-child[data-key=nvd]", text: /NVD \(NIST\).*note CVSS.*0 CVE notées.*HTTP 503/m
    assert_select "li.score-provider[data-key=redhat]", text: /1 CVE notées/
    assert_select "li.score-provider[data-key=kev]", text: /exploitation/
    assert_select "li.score-provider[data-key=nvd] form[action=?]", test_settings_score_provider_path(provider("nvd"))
    assert_select "li.score-provider[data-key=nvd] button[disabled][aria-label='Monter NVD (NIST)']"
    assert_select "a[href=?]", new_settings_score_provider_path
  end

  test "reorders and toggles a provider" do
    patch move_settings_score_provider_path(provider("redhat"), direction: "up")
    assert_equal %w[redhat nvd cveorg epss kev], ScoreProvider.ordered.pluck(:key)

    patch toggle_settings_score_provider_path(provider("nvd"))
    assert_not provider("nvd").enabled?
    assert_redirected_to settings_vulnerabilities_path(anchor: "score-providers")
  end

  test "adds, edits and removes a custom provider" do
    get new_settings_score_provider_path
    assert_select "form.score-provider-form input[name='score_provider[url_template]']"

    post settings_score_providers_path, params: { score_provider: { name: "CVEFind", url_template: "http://bad", format: "html" } }
    assert_response :unprocessable_entity
    assert_select ".score-provider-form", text: /https:\/\/ et contenir \{cve\}/

    post settings_score_providers_path, params: { score_provider: { name: "CVEFind", url_template: "https://www.cvefind.com/fr/cve/{cve}.html", format: "html",
                                                                   regex: '"Base Score",\s*"value": "([\d.]+)"', delay_ms: "1500", max_per_run: "100" } }
    custom = ScoreProvider.find_by!(kind: "custom")
    assert_equal [ "CVEFind", 1500, 100, 5 ], [ custom.name, custom.setting("delay_ms"), custom.setting("max_per_run"), custom.position ]
    assert_equal "https://www.cvefind.com/fr/cve/CVE-2024-6387.html", custom.page_url("CVE-2024-6387")

    patch settings_score_provider_path(custom), params: { score_provider: { name: "CVE Find", url_template: custom.setting("url_template"), format: "html", css_selector: ".cvss-score" } }
    assert_equal [ "CVE Find", ".cvss-score" ], [ custom.reload.name, custom.setting("css_selector") ]

    delete settings_score_provider_path(custom)
    assert_not ScoreProvider.exists?(custom.id)
    get edit_settings_score_provider_path(provider("nvd"))
    assert_response :not_found
  end

  test "tests a provider on a CVE, saved or from the form, without storing anything" do
    with_score_answers("hydra/rest" => "redhat-CVE-2024-6387.json", "cvefind.com" => "custom-page.html") do
      post test_settings_score_provider_path(provider("redhat")), params: { cve: "cve-2024-6387" }, as: :turbo_stream
      assert_select "turbo-stream[target=?]", "score-provider-test-#{provider("redhat").id}"
      assert_match "CVE-2024-6387 : <strong>8,1</strong>", response.body

      post preview_settings_score_providers_path, params: { cve: "CVE-2024-6387", score_provider: { name: "CVEFind", url_template: "https://www.cvefind.com/fr/cve/{cve}.html",
                                                                                                   format: "html", css_selector: ".cvss-score" } }, as: :turbo_stream
      assert_select "turbo-stream[target=score-provider-test-new]"
      assert_match "<strong>8,1</strong>", response.body

      post test_settings_score_provider_path(provider("redhat")), params: { cve: "pas une cve" }, as: :turbo_stream
      assert_match "Indiquez une CVE", response.body
    end
    assert_equal 0, CveScore.count
  end

  test "the detail of a CVE: scores by provider, vector in words, exploitation, packages, servers" do
    vulnerable(servers(:web), "CVE-2024-6387")
    vulnerable(servers(:db), "CVE-2024-6387", fixed: nil)
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 8.1, version: "3.1", vector: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", data: { "description" => "regreSSHion" } } ])
    CveScore.store("redhat", [ { cve: "CVE-2024-6387", score: 8.1, version: "3" } ])
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
    CveRating.refresh!
    sign_in users(:viewer)

    get vulnerability_path("CVE-2024-6387", server_id: servers(:web).id), headers: { "Turbo-Frame" => "vulnerability-detail" }

    assert_response :success
    assert_select "aside.sidebar", 0, "frame request: no layout"
    assert_select "turbo-frame#vulnerability-detail .vulnerability-detail[data-cve=CVE-2024-6387]" do
      assert_select ".detail-score", text: /8,1/
      assert_select ".detail-exploited", text: /Exploitée activement.*3 juillet 2024/
      assert_select ".detail-description", "regreSSHion"
      assert_select "li.detail-provider-score[data-provider=nvd]", text: /8,1\s+NVD \(NIST\)\s+CVSS 3.1.*Vecteur : réseau.*Complexité : élevée/m
      assert_select "li.detail-provider-score[data-provider=nvd] a[href=?]", "https://nvd.nist.gov/vuln/detail/CVE-2024-6387"
      assert_select "li.detail-provider-score[data-provider=redhat] a[href=?]", "https://access.redhat.com/security/cve/cve-2024-6387"
      assert_select ".detail-on-server", text: /Sur Web.*openssh.*openssh-server.*1.0.*2.0/m
      assert_select ".detail-servers li", 2
      assert_select ".detail-servers", text: /Database.*Web.*corrigeable/m
    end
    assert_select "span", text: /déduite de la note/

    get vulnerability_path("CVE-2024-6387")
    assert_select "aside.sidebar" # as a page: with the layout
    get vulnerability_path("CVE-2099-0001")
    assert_response :not_found
  end

  test "the modal lists every enabled provider, asked or not, each score in a pill of its colour" do
    vulnerable(servers(:web), "CVE-2024-6387")
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 9.3, version: "3.1" } ])
    CveScore.store("cveorg", [ { cve: "CVE-2024-6387", score: nil } ])
    CveRating.refresh!
    sign_in users(:viewer)

    get vulnerability_path("CVE-2024-6387", server_id: servers(:web).id), headers: { "Turbo-Frame" => "vulnerability-detail" }

    assert_select "li.detail-provider-score", 3, "NVD, Red Hat, CVE.org; EPSS and KEV apart"
    assert_select "li.detail-provider-score[data-provider=nvd] .score-pill[data-color=red]", "9,3"
    assert_select "li.detail-provider-score[data-provider=redhat] .provider-asking", /demande en cours/
    assert_select "li.detail-provider-score[data-provider=cveorg]", /pas de note chez ce fournisseur/
    assert_select ".detail-score .score-pill[data-color=red]", "9,3"
  end

  test "opening a CVE asks at once the providers that never answered, the page reloads until they did" do
    vulnerable(servers(:web), "CVE-2024-6387")
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 9.3, version: "3.1" } ])
    sign_in users(:viewer)

    assert_enqueued_with(job: FetchCveScoresJob, args: [ "CVE-2024-6387" ]) do
      get vulnerability_path("CVE-2024-6387"), headers: { "Turbo-Frame" => "vulnerability-detail" }
    end
    assert_select "li.detail-provider-score[data-provider=redhat] .provider-asking", /demande en cours/
    assert_select "turbo-frame#vulnerability-detail [data-controller=auto-refresh]"

    assert_no_enqueued_jobs { get vulnerability_path("CVE-2024-6387"), headers: { "Turbo-Frame" => "vulnerability-detail" } }
    assert_select "[data-controller=auto-refresh]", 1, "still being asked"

    with_score_answers("access.redhat.com" => "redhat-CVE-2024-6387.json", "cveawg.mitre.org" => :limited) { perform_enqueued_jobs }
    get vulnerability_path("CVE-2024-6387"), headers: { "Turbo-Frame" => "vulnerability-detail" }
    assert_select "li.detail-provider-score[data-provider=redhat] .score-pill", "8,1"
    assert_select "li.detail-provider-score[data-provider=cveorg] .provider-pending", /pas encore demandé \(prochain passage des notes\)/, "asked again in an hour at most"
    assert_select "[data-controller=auto-refresh]", 0

    CveScore.store("nvd", [ { cve: "CVE-2023-0001", score: 5.0 } ])
    assert_no_enqueued_jobs { get vulnerability_path("CVE-2023-0001") }
    assert_response :success
    assert_select ".provider-asking", 0, "only the CVEs of the fleet are asked"
  end

  test "the detail of a CVE lists its Debian and Ubuntu advisories and its fixes" do
    vulnerable(servers(:web), "CVE-2024-6387")
    references = [ { "url" => "https://www.debian.org/security/2024/dsa-5724", "kind" => "advisory" },
                   { "url" => "https://github.com/openssh/openssh-portable/commit/81c1099d22b81ebfd20a334ce986c4f753b0db29", "kind" => "fix" } ]
    %w[nvd redhat cveorg].each { |key| CveScore.store(key, [ { cve: "CVE-2024-6387", score: 8.1, data: (key == "nvd" ? { "references" => references } : {}) } ]) }
    sign_in users(:viewer)

    assert_no_enqueued_jobs { get vulnerability_path("CVE-2024-6387") }

    assert_select ".detail-references [data-kind=advisory]", text: /Avis\s+DSA-5724/
    assert_select ".detail-references [data-kind=advisory] a[href=?][target=_blank][rel='noopener noreferrer']", "https://www.debian.org/security/2024/dsa-5724"
    assert_select ".detail-references [data-kind=fix]", text: /Correctifs\s+github\.com/
    assert_select "[data-controller=auto-refresh]", 0
  end

  test "the score colours are set in the settings and used in the lists" do
    vulnerable(servers(:web), "CVE-2024-6387")
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 6.5 } ])
    CveRating.refresh!

    get settings_vulnerabilities_path
    assert_select "#score-colors .score-band", 3

    patch settings_vulnerabilities_path, params: { app_setting: { score_bands_form: { "0" => { from: "0", color: "gray" }, "1" => { from: "5,5", color: "blue" }, "2" => { from: "9", color: "red" } } } }
    assert_redirected_to settings_vulnerabilities_path(anchor: "score-colors")
    assert_equal [ 0.0, 5.5, 9.0 ], AppSetting.current.score_bands.map { |band| band["from"] }

    get server_path(servers(:web), tab: "vulnerabilities", view: "cves")
    assert_select "tr.server-vulnerability .score-pill[data-color=blue]", "6,5"

    patch settings_vulnerabilities_path, params: { app_setting: { score_bands_form: { "0" => { from: "0", color: "green" }, "1" => { from: "8", color: "orange" }, "2" => { from: "7", color: "pink" } } } }
    assert_match "montent jusqu'à 10", flash[:alert]
    assert_match "couleur inconnue", flash[:alert]
    assert_equal "blue", AppSetting.current.reload.score_bands[1]["color"]
  end
end
