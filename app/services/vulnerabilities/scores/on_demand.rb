# Scores asked for when the page of a CVE is opened: the enabled CVSS
# providers that never answered for it are asked at once, in the background
# (FetchCveScoresJob), instead of waiting for the next scores run. Through
# the same providers (no other address), one job at a time at each
# provider's pace, a CVE at most once per AGAIN, at most PER_HOUR CVEs an hour.
module Vulnerabilities::Scores::OnDemand
  CVE = /\ACVE-\d{4}-\d{4,}\z/
  # The page shows "being asked" and reloads itself for so long at most.
  PENDING = 5.minutes
  AGAIN = 1.hour
  PER_HOUR = 30

  # Shared by the web and the jobs (Solid Cache); in memory where the cache keeps nothing (tests).
  STORE = Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  # The enabled CVSS providers that have nothing stored for the CVE.
  def self.missing(cve, providers: ScoreProvider.all_providers)
    asked = CveScore.where(cve: cve).pluck(:provider_key)
    providers.select { |provider| provider.enabled? && provider.cvss? && asked.exclude?(provider.key) }
  end

  # Queues the request of the missing scores; true when queued now.
  def self.request(cve, providers: ScoreProvider.all_providers)
    return false unless cve.match?(CVE) && missing(cve, providers: providers).any?
    return false unless STORE.write("cve-scores/asked/#{cve}", true, expires_in: AGAIN, unless_exist: true)
    return false if STORE.increment("cve-scores/hour/#{Time.current.strftime("%Y%m%d%H")}", 1, expires_in: 2.hours).to_i > PER_HOUR

    STORE.write("cve-scores/pending/#{cve}", true, expires_in: PENDING)
    FetchCveScoresJob.perform_later(cve)
    true
  end

  def self.pending?(cve) = STORE.exist?("cve-scores/pending/#{cve}")

  # The job: each missing provider in turn; one that fails is left for the scores run.
  def self.fetch(cve)
    asked = missing(cve).count do |provider|
      Vulnerabilities::Scores.fetcher(provider).fetch_one(cve)
      true
    rescue Integrations::Error, Vulnerabilities::Error => e
      Rails.logger.info("Score of #{cve} at #{provider.key} not available now: #{e.message}")
      false
    end
    CveRating.refresh!([ cve ]) if asked.positive?
  ensure
    STORE.delete("cve-scores/pending/#{cve}")
  end
end
