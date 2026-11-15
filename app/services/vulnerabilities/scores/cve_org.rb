# CVE.org (CVE Services API, cveawg.mitre.org/api/cve/<CVE>): the CVSS of the
# CNA that published the CVE, else the one added by CISA (ADP "Vulnrichment").
# The most recent CVSS version first; the advisories and fixes among the
# references of both.
class Vulnerabilities::Scores::CveOrg < Vulnerabilities::Scores::Base
  URL = "https://cveawg.mitre.org/api/cve/{cve}"
  METRICS = { "cvssV4_0" => "4.0", "cvssV3_1" => "3.1", "cvssV3_0" => "3.0", "cvssV2_0" => "2.0" }.freeze

  def fetch(cves) = fetch_each(cves)

  def lookup(cve)
    body = get(url_for(URL, cve)) or return nil
    record = JSON.parse(body)
    return nil unless record.is_a?(Hash)

    cna = record.dig("containers", "cna") || {}
    cisa = Array(record.dig("containers", "adp")).find { |adp| adp.dig("providerMetadata", "shortName") == "CISA-ADP" } || {}
    references = Vulnerabilities::References.pick(Array(cna["references"]) + Array(cisa["references"])).presence
    [ [ cna, "CNA" ], [ cisa, "CISA" ] ].each do |container, from|
      METRICS.each do |key, version|
        metric = Array(container["metrics"]).filter_map { |entry| entry[key] }.first
        next unless metric && (score = cvss(metric["baseScore"]))

        return Score.new(score: score, version: version, vector: metric["vectorString"], severity: metric["baseSeverity"]&.downcase, data: { "from" => from, "references" => references }.compact)
      end
    end
    nil
  rescue JSON::ParserError
    raise Integrations::Error, I18n.t("vulnerabilities.scores.cve_org.unreadable", cve: cve)
  end
end
