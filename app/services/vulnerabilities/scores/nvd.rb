require "zlib"

# NVD (NIST) in bulk: the JSON 2.0 feed of each year of the fleet's CVEs
# (nvdcve-2.0-2024.json.gz, 25-45 MB, streamed), downloaded again after
# YEAR_REFRESH, plus the feed of the last days' changes at each run. Only the
# CVEs of the fleet are kept; a year with few of them (< bulk_from) is asked
# through the NVD API instead (5 requests per 30 s without a key). The score is the NVD's own (Primary) one, else a
# Secondary one, the most recent CVSS version first, with the advisories and
# fixes among its references. `test` asks the NVD API.
class Vulnerabilities::Scores::Nvd < Vulnerabilities::Scores::Base
  FEED = ENV.fetch("ELIO_NVD_FEED_URL", "https://nvd.nist.gov/feeds/json/cve/2.0/nvdcve-2.0-%{name}.json.gz")
  API = "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={cve}"
  METRICS = { "cvssMetricV40" => "4.0", "cvssMetricV31" => "3.1", "cvssMetricV30" => "3.0", "cvssMetricV2" => "2.0" }.freeze
  YEAR_REFRESH = 30.days
  # Fewer CVEs of a year on the fleet than this: the API rather than its feed.
  cattr_accessor :bulk_from, default: 30

  def fetch(cves)
    wanted = cves.to_set
    by_year = cves.group_by { |cve| cve[/\ACVE-(\d{4})-/, 1] }.except(nil)
    few = by_year.select { |_, list| list.size < bulk_from }.values.flatten
    years = (by_year.keys - by_year.select { |_, list| list.size < bulk_from }.keys).sort
    state = provider.state.dup
    fetched = state.fetch("years", {})
    stale = years.select { |year| fetched[year].nil? || Time.zone.parse(fetched[year]) < YEAR_REFRESH.ago }
    count = 0
    stale.each do |year|
      found = read_feed(year, wanted)
      # A CVE of that year absent from its feed has no NVD score (yet).
      missing = cves.select { |cve| cve.start_with?("CVE-#{year}-") } - found
      CveScore.store(provider.key, missing.map { |cve| { cve: cve, score: nil } })
      fetched[year] = Time.current.iso8601
      count += found.size + missing.size
    end
    count += read_feed("modified", wanted).size if stale.size < years.size || years.empty?
    provider.update!(state: state.merge("years" => fetched))
    count + fetch_each(few)
  end

  def lookup(cve)
    body = get(url_for(API, cve)) or return nil
    item = Array(JSON.parse(body)["vulnerabilities"]).first
    item && score_of(item["cve"])
  rescue JSON::ParserError
    raise Integrations::Error, I18n.t("vulnerabilities.scores.nvd.unreadable", cve: cve)
  end

  # Stores the scores of the wanted CVEs of a feed; returns their ids.
  def read_feed(name, wanted)
    found = []
    batch = []
    Vulnerabilities::Download.open(format(FEED, name: name)) do |path|
      Zlib::GzipReader.open(path) do |gzip|
        Vulnerabilities::JsonObjectStream.each_element(gzip, key: "vulnerabilities") do |item|
          cve = item.dig("cve", "id")
          next unless wanted.include?(cve)

          found << cve
          batch << { cve: cve, **(score_of(item["cve"])&.to_h || { score: nil }) }
          (CveScore.store(provider.key, batch); batch.clear) if batch.size >= 1000
        end
      end
    end
    CveScore.store(provider.key, batch)
    found
  rescue Vulnerabilities::JsonObjectStream::Error, Zlib::Error, JSON::ParserError => e
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.scores.nvd.unreadable_feed", name: name, truncate: (e.message.truncate(120)))
  end

  def score_of(record)
    metrics = record["metrics"] || {}
    description = Array(record["descriptions"]).find { |entry| entry["lang"] == "en" }&.dig("value")
    METRICS.each do |key, version|
      entries = Array(metrics[key])
      metric = entries.find { |entry| entry["type"] == "Primary" } || entries.first
      data = metric&.dig("cvssData") or next
      next unless (score = cvss(data["baseScore"]))

      return Score.new(score: score, version: version, vector: data["vectorString"], severity: (data["baseSeverity"] || metric["baseSeverity"])&.downcase,
                       data: { "source" => metric["source"], "description" => description&.truncate(600),
                               "references" => Vulnerabilities::References.pick(record["references"]).presence }.compact)
    end
    nil
  end
end
