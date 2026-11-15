require "test_helper"

class CveRatingTest < ActiveSupport::TestCase
  include ScoreHelpers
  include StubHelpers

  setup do
    custom_provider("regex" => "(.+)")
    vulnerable(servers(:web), "CVE-2024-6387")
    vulnerable(servers(:web), "CVE-2024-0002", severity: "low")
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 8.1 }, { cve: "CVE-2024-0002", score: 9.8 } ])
    CveScore.store("redhat", [ { cve: "CVE-2024-6387", score: nil } ])
    CveScore.store("custom-test", [ { cve: "CVE-2024-6387", score: 9.3 } ])
    CveScore.store("epss", [ { cve: "CVE-2024-6387", score: 0.99506, data: { "percentile" => 0.99946 } } ])
    CveScore.store("kev", [ { cve: "CVE-2024-6387", score: 1, data: { "date_added" => "2024-07-03" } } ])
  end

  test "the average CVSS of the enabled providers, EPSS and KEV apart" do
    CveRating.refresh!
    rating = CveRating.find_by!(cve: "CVE-2024-6387")
    assert_equal [ 8.7, 2, 0.99506, true, Date.new(2024, 7, 3) ], [ rating.score.to_f, rating.scores_count, rating.epss.to_f, rating.exploited, rating.exploited_since ]

    provider("custom-test").update!(enabled: false)
    CveRating.refresh!
    assert_equal [ 8.1, 1 ], CveRating.find_by!(cve: "CVE-2024-6387").then { [ it.score.to_f, it.scores_count ] }
  end

  test "the score gives the severity when the distribution did not rate, never otherwise" do
    CveRating.refresh!
    assert_equal [ "high", "unknown" ], servers(:web).server_vulnerabilities.find_by!(cve: "CVE-2024-6387").then { [ it.severity, it.distro_severity ] }
    assert_equal "low", servers(:web).server_vulnerabilities.find_by!(cve: "CVE-2024-0002").severity, "Debian rated it low: 9.8 does not change it"
    assert servers(:web).server_vulnerabilities.find_by!(cve: "CVE-2024-6387").severity_from_score?
  end

  test "a CVE that becomes serious through its score is logged and becomes a health reason" do
    CveRating.refresh!
    assert_equal "1 vulnérabilité corrigeable sur « Web » : CVE-2024-6387 (openssh)", Activity.of_kind(:vulnerability_found).sole.summary
    assert_includes servers(:web).reload.health_reason_texts, "Vulnérabilité CVE-2024-6387 corrigeable"

    CveRating.refresh!
    assert_equal 1, Activity.of_kind(:vulnerability_found).count, "already serious"
  end

  test "a CVE newly listed as exploited alerts whatever its severity" do
    CveRating.refresh!
    assert_not_includes servers(:web).reload.health_reason_texts.join, "CVE-2024-0002"

    CveScore.store("kev", [ { cve: "CVE-2024-0002", score: 1, data: { "date_added" => "2026-11-15" } } ])
    CveRating.refresh!
    assert_equal [ "CVE-2024-0002" ], Activity.of_kind(:vulnerability_found).order(:id).last.data["cves"], "low, but exploited"
    assert_includes servers(:web).reload.health_reason_texts, "2 vulnérabilités graves corrigeables"
  end

  test "new rows take the severity of the known score" do
    CveRating.refresh!
    Vulnerabilities::Matcher.replace(servers(:db), [ { server_id: servers(:db).id, origin: "host", source: "debian", image: nil, cve: "CVE-2024-6387", source_package: "openssh",
                                                       packages: [ "openssh-server" ], installed_version: "1", fixed_version: "2", severity: "unknown", description: nil } ], origin: "host", log: false)
    assert_equal [ "high", "unknown" ], servers(:db).server_vulnerabilities.sole.then { [ it.severity, it.distro_severity ] }
  end

  test "update_all runs every enabled provider and keeps the error of the one that fails" do
    stub_method(Vulnerabilities::Download, :open, ->(*, **) { raise Vulnerabilities::Error, "HTTP 503" }) do
      with_score_answers({}) do
        result = Vulnerabilities::Scores.update_all(cves: %w[CVE-2024-6387])
        assert_match "1 CVE · NVD (NIST) : échec · Red Hat : 0", result
      end
    end
    assert_equal "HTTP 503", provider("nvd").last_error
    assert_nil provider("redhat").last_error
  end

  test "a score of 10.0 is stored (found on CVE.org)" do
    CveScore.store("cveorg", [ { cve: "CVE-2024-6387", score: 10.0 } ])
    CveRating.refresh!
    assert_equal 10.0, CveScore.find_by!(provider_key: "cveorg").score.to_f
    assert_equal 9.1, CveRating.find_by!(cve: "CVE-2024-6387").score.to_f, "(8.1 + 9.3 + 10) / 3"
  end

  test "severity from a score" do
    assert_equal %w[critical high medium low unknown], [ 9.0, 7.0, 4.0, 0.1, nil ].map { |score| CveRating.severity_for(score) }
  end
end
