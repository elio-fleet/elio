require "test_helper"

class Vulnerabilities::Scores::ProvidersTest < ActiveSupport::TestCase
  include StubHelpers
  include ScoreHelpers

  CVE = "CVE-2024-6387"

  setup { Vulnerabilities::Scores::Nvd.bulk_from = 1 }
  teardown { Vulnerabilities::Scores::Nvd.bulk_from = 30 }

  def lookup(key, cve = CVE) = Vulnerabilities::Scores.fetcher(provider(key)).test(cve)

  test "Red Hat: its CVSS v3 score, vector and severity" do
    with_score_answers("hydra/rest/securitydata/cve/CVE-2024-6387.json" => "redhat-CVE-2024-6387.json") do
      score = lookup("redhat")
      assert_equal [ 8.1, "3", "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", "Important" ], [ score.score, score.version, score.vector, score.severity ]
      assert_nil lookup("redhat", "CVE-2024-0002"), "404: unknown to Red Hat"
    end
  end

  test "Red Hat: a recent CVE answered JSON-encoded twice (real answer)" do
    with_score_answers("CVE-2026-98902" => "redhat-double-encoded.json") do
      assert_equal [ 4.7, "Moderate" ], lookup("redhat", "CVE-2026-98902").then { [ it.score, it.severity ] }
    end
  end

  test "an unexpected error stops its provider only" do
    stub_method(Vulnerabilities::Scores::RedHat, :new, ->(*) { raise NoMethodError, "boom" }) do
      with_score_downloads({}) do
        result = Vulnerabilities::Scores.update_all(cves: [])
        assert_match "Red Hat : échec", result
      end
    end
    assert_match "Erreur interne (NoMethodError)", provider("redhat").last_error
  end

  test "CVE.org: the score of the CNA" do
    with_score_answers("cveawg.mitre.org/api/cve/CVE-2024-6387" => "cveorg-CVE-2024-6387.json") do
      score = lookup("cveorg")
      assert_equal [ 8.1, "3.1", "high", "CNA" ], [ score.score, score.version, score.severity, score.data["from"] ]
      assert_equal [], score.data.fetch("references", []).reject { |reference| reference["kind"] == "fix" }, "Red Hat errata are not Debian or Ubuntu advisories"
    end
  end

  test "NVD: the API for a test, the most recent CVSS version, Primary first" do
    with_score_answers("services.nvd.nist.gov" => "nvd-api-CVE-2024-6387.json") do
      score = lookup("nvd")
      assert_equal [ 8.1, "3.1" ], [ score.score, score.version ]
      assert_match "regression", score.data["description"]
      references = score.data["references"].to_h { |reference| [ reference["url"], reference["kind"] ] }
      assert_equal "advisory", references["https://ubuntu.com/security/notices/USN-6859-1"]
      assert_equal "fix", references["https://github.com/openela-main/openssh/commit/e1f438970e5a337a17070a637c1b9e19697cad09"]
      assert_nil references["https://access.redhat.com/errata/RHSA-2024:4312"]
      assert_equal "advisory", score.data["references"].first["kind"], "advisories first"
    end
  end

  test "NVD: the yearly feeds of the fleet's CVEs once a month, the changes at each run" do
    nvd = provider("nvd")
    files = { "nvdcve-2.0-2024" => "nvdcve-2.0-2024.json.gz", "nvdcve-2.0-modified" => "nvdcve-2.0-modified.json.gz" }
    with_score_downloads(files) do |downloaded|
      assert_equal 2, Vulnerabilities::Scores.fetcher(nvd).fetch(%w[CVE-2024-6387 CVE-2024-0002])
      assert_equal [ "https://nvd.nist.gov/feeds/json/cve/2.0/nvdcve-2.0-2024.json.gz" ], downloaded, "no changes feed when every year was just read"
      assert_equal({ "CVE-2024-6387" => 8.1, "CVE-2024-0002" => nil }, CveScore.where(provider_key: "nvd").pluck(:cve, :score).to_h { |cve, score| [ cve, score&.to_f ] })
      assert_not CveScore.exists?(cve: "CVE-2099-0001"), "not on the fleet"

      downloaded.clear
      error = assert_raises(Vulnerabilities::Error) { Vulnerabilities::Scores.fetcher(nvd.reload).fetch(%w[CVE-2024-6387 CVE-2026-0001]) }
      assert_match "nvdcve-2.0-2026", error.message, "a new year of the fleet: its feed is downloaded (here missing: the run stops)"
      assert_equal [ "https://nvd.nist.gov/feeds/json/cve/2.0/nvdcve-2.0-2026.json.gz" ], downloaded, "2024 was read less than a month ago"
    end
  end

  test "NVD: a year already read only needs the changes feed (CVSS 4.0 kept)" do
    nvd = provider("nvd")
    nvd.update!(state: { "years" => { "2024" => Time.current.iso8601, "2026" => Time.current.iso8601 } })
    with_score_downloads("nvdcve-2.0-modified" => "nvdcve-2.0-modified.json.gz") do |downloaded|
      Vulnerabilities::Scores.fetcher(nvd).fetch(%w[CVE-2024-6387 CVE-2026-0001])
      assert_equal [ "https://nvd.nist.gov/feeds/json/cve/2.0/nvdcve-2.0-modified.json.gz" ], downloaded
    end
    assert_equal [ 9.3, "4.0", "critical" ], CveScore.find_by!(cve: "CVE-2026-0001").then { [ it.score.to_f, it.version, it.severity ] }
  end

  test "NVD: a year with few CVEs on the fleet goes through the API" do
    Vulnerabilities::Scores::Nvd.bulk_from = 30
    with_score_answers("cveId=CVE-2024-6387" => "nvd-api-CVE-2024-6387.json") do
      with_score_downloads("nvdcve-2.0-modified" => "nvdcve-2.0-modified.json.gz") do |downloaded|
        Vulnerabilities::Scores.fetcher(provider("nvd")).fetch(%w[CVE-2024-6387])
        assert_equal [ "https://nvd.nist.gov/feeds/json/cve/2.0/nvdcve-2.0-modified.json.gz" ], downloaded
      end
    end
    assert_equal 8.1, CveScore.find_by!(provider_key: "nvd", cve: "CVE-2024-6387").score.to_f
  end

  test "EPSS and KEV: daily files, only the fleet's CVEs" do
    with_score_downloads("epss_scores" => "epss.csv.gz", "known_exploited" => "kev.json") do
      Vulnerabilities::Scores.fetcher(provider("epss")).fetch(%w[CVE-2024-6387 CVE-2024-0002])
      Vulnerabilities::Scores.fetcher(provider("kev")).fetch(%w[CVE-2024-6387 CVE-2024-0002])
    end
    epss = CveScore.find_by!(provider_key: "epss", cve: "CVE-2024-6387")
    assert_equal [ 0.99506, 0.99946 ], [ epss.score.to_f, epss.data["percentile"] ]
    assert_nil CveScore.find_by!(provider_key: "epss", cve: "CVE-2024-0002").score
    assert_equal 1, CveScore.find_by!(provider_key: "kev", cve: "CVE-2024-6387").score
    assert_nil CveScore.find_by!(provider_key: "kev", cve: "CVE-2024-0002").score
    assert_not CveScore.exists?(cve: "CVE-1999-0001")
  end

  test "custom HTML provider: a regex, or a CSS selector" do
    with_score_answers("cvefind.com/fr/cve/CVE-2024-6387.html" => "custom-page.html") do
      regex = custom_provider("regex" => '"name": "Base Score",\s*"value": "([\d.]+)"')
      assert_equal 8.1, Vulnerabilities::Scores.fetcher(regex).test(CVE).score
      regex.update!(settings: regex.settings.except("regex").merge("css_selector" => ".cvss-score"))
      assert_equal 8.1, Vulnerabilities::Scores.fetcher(regex).test(CVE).score, "« Score : 8,1 »"
      regex.update!(settings: regex.settings.merge("css_selector" => ".missing"))
      assert_nil Vulnerabilities::Scores.fetcher(regex).test(CVE)
    end
  end

  test "custom JSON provider: a dotted path with indexes" do
    with_score_answers("example.test/cve/CVE-2024-6387" => "cveorg-CVE-2024-6387.json") do
      json = custom_provider("url_template" => "https://example.test/cve/{cve}", "format" => "json", "json_path" => "containers.cna.metrics.1.cvssV3_1.baseScore")
      assert_equal 8.1, Vulnerabilities::Scores.fetcher(json).test(CVE).score
    end
  end

  test "per-CVE providers: never asked first, at most max_per_run, a rate limit stops the run" do
    custom = custom_provider("regex" => "(\\d+\\.\\d+)", "max_per_run" => 2)
    CveScore.store(custom.key, [ { cve: "CVE-2024-0003", score: 5.0 } ])
    with_score_answers("CVE-2024-0001" => "custom-page.html", "CVE-2024-0002" => :not_found, "CVE-2024-0004" => :limited) do
      assert_equal 2, Vulnerabilities::Scores.fetcher(custom).fetch(%w[CVE-2024-0001 CVE-2024-0002 CVE-2024-0003])
      assert_equal 8.1, CveRating.find_by!(cve: "CVE-2024-0001").score.to_f, "rated as soon as asked, without waiting for the end of the run"
      assert_equal({ "CVE-2024-0001" => 8.1, "CVE-2024-0002" => nil, "CVE-2024-0003" => 5.0 }, custom.scores.pluck(:cve, :score).to_h { |cve, score| [ cve, score&.to_f ] })
      error = assert_raises(Vulnerabilities::Error) { Vulnerabilities::Scores.fetcher(custom).fetch(%w[CVE-2024-0004]) }
      assert_match "429", error.message
    end
  end

  test "a custom provider is validated" do
    provider = ScoreProvider.new(key: "custom-x", kind: "custom").assign_custom(name: "X", url_template: "http://x.test/", format: "html", regex: "(", delay_ms: 10)
    assert_not provider.valid?
    assert_equal [ "L'adresse doit commencer par https:// et contenir {cve}", "Délai entre deux requêtes : 200 ms minimum" ], provider.errors.full_messages - provider.errors.full_messages.grep(/Regex/)
    assert_match "Regex invalide", provider.errors.full_messages.grep(/Regex/).sole
    I18n.with_locale(:en) { assert_includes provider.tap(&:valid?).errors.full_messages, "The address must start with https:// and contain {cve}" }

    json = ScoreProvider.new(key: "custom-y", kind: "custom").assign_custom(name: "Y", url_template: "https://y.test/{cve}", format: "json")
    assert_equal [ "Indiquez le chemin JSON de la note (ex. cvss3.cvss3_base_score)" ], json.tap(&:valid?).errors.full_messages
  end
end
