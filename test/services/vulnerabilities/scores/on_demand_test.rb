require "test_helper"

class Vulnerabilities::Scores::OnDemandTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include StubHelpers
  include ScoreHelpers

  OnDemand = Vulnerabilities::Scores::OnDemand
  CVE = "CVE-2024-6387"

  test "the providers never asked for a CVE are asked once, in the background" do
    CveScore.store("nvd", [ { cve: CVE, score: nil } ])

    assert_enqueued_with(job: FetchCveScoresJob, args: [ CVE ]) { assert OnDemand.request(CVE) }
    assert OnDemand.pending?(CVE)
    assert_equal %w[redhat cveorg], OnDemand.missing(CVE).map(&:key), "a CVSS provider already asked waits for its refresh; EPSS and KEV come in bulk"

    assert_no_enqueued_jobs { assert_not OnDemand.request(CVE) }
    assert_no_enqueued_jobs { assert_not OnDemand.request("GHSA-xxxx-yyyy-zzzz") }
    %w[nvd redhat cveorg].each { |key| CveScore.store(key, [ { cve: "CVE-2024-0002", score: 5.0 } ]) }
    assert_no_enqueued_jobs { assert_not OnDemand.request("CVE-2024-0002") }
  end

  test "at most PER_HOUR CVEs an hour" do
    OnDemand::PER_HOUR.times { |index| assert OnDemand.request(format("CVE-2024-%04d", index + 1000)) }
    assert_not OnDemand.request("CVE-2024-9999")
  end

  test "the job stores each missing score and the rating; a provider that fails is left for the scores run" do
    OnDemand.request(CVE)
    answers = { "services.nvd.nist.gov" => "nvd-api-CVE-2024-6387.json", "access.redhat.com" => :limited, "cveawg.mitre.org" => "cveorg-CVE-2024-6387.json" }

    with_score_answers(answers) { FetchCveScoresJob.perform_now(CVE) }

    assert_equal({ "nvd" => 8.1, "cveorg" => 8.1 }, CveScore.where(cve: CVE).pluck(:provider_key, :score).to_h { |key, score| [ key, score.to_f ] })
    assert_equal 8.1, CveRating.find_by!(cve: CVE).score.to_f
    assert_not OnDemand.pending?(CVE)
    assert_equal %w[redhat], OnDemand.missing(CVE).map(&:key)
  end
end
