# The scores of one CVE whose page was opened (Vulnerabilities::Scores::OnDemand).
# One at a time: the providers' pace holds across the requests of several pages.
class FetchCveScoresJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "cve-scores-on-demand", duration: 15.minutes

  def perform(cve) = Vulnerabilities::Scores::OnDemand.fetch(cve)
end
