# A score provider: `fetch(cves)` stores what it knows of those CVEs
# (CveScore) and returns how many it asked about; `fetch_one(cve)` asks for
# one CVE right away; `test(cve)` returns the Score it would store, without
# storing it (the settings' test button).
class Vulnerabilities::Scores::Base
  Score = Data.define(:score, :version, :vector, :severity, :data) do
    def initialize(score:, version: nil, vector: nil, severity: nil, data: {}) = super
  end

  # Pause after a "too many requests" or an error streak: the provider is left for the next run.
  MAX_ERRORS = 5
  # Ratings refreshed every so many CVEs during a long run (the lists show them at once).
  REFRESH_EVERY = 100

  attr_reader :provider

  def initialize(provider)
    @provider = provider
  end

  def test(cve) = lookup(cve)

  # One CVE at once (its page was opened), stored like in a run, then a
  # pause at the provider's pace before the next request.
  def fetch_one(cve)
    score = lookup(cve)
    CveScore.store(provider.key, [ { cve: cve, **(score&.to_h || { score: nil }) } ])
  ensure
    sleep(provider.setting("delay_ms").to_f / 1000) if pause?
  end

  private

  # One request per CVE, at the provider's pace (delay_ms), at most
  # max_per_run, never asked ones first.
  def fetch_each(cves)
    due = CveScore.due(provider.key, cves).first(provider.setting("max_per_run").to_i)
    errors = 0
    done = []
    due.each_with_index do |cve, index|
      sleep(provider.setting("delay_ms").to_f / 1000) if index.positive? && pause?
      score = lookup(cve)
      CveScore.store(provider.key, [ { cve: cve, **(score&.to_h || { score: nil }) } ])
      errors = 0
      done << cve
      if done.size >= REFRESH_EVERY
        CveRating.refresh!(done)
        done = []
      end
    rescue Integrations::Error => e
      raise Vulnerabilities::Error, e.message if e.message.include?(" 429") || (errors += 1) >= MAX_ERRORS
    end
    due.size
  ensure
    CveRating.refresh!(done) if done.present?
  end

  # Tests run without waiting between requests.
  def pause? = !Rails.env.test?

  def get(url, accept: "application/json")
    Integrations::Http.get(url, service: provider.name, headers: { "Accept" => accept })
  rescue Integrations::Error => e
    raise unless e.message.include?(" 404 ")

    nil # the provider does not know this CVE
  end

  def url_for(template, cve) = template.gsub("{cve}", ERB::Util.url_encode(cve))

  # A CVSS score as a number between 0 and 10, or nil.
  def cvss(value)
    number = Float(value.to_s.tr(",", "."), exception: false)
    number if number && number.between?(0, 10)
  end
end
