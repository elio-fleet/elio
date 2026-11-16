# Daily digest of a notification channel: the fleet state and the activities
# of the period (yesterday by default), the warnings and critical ones listed.
class NotificationDigest
  HIGHLIGHTS = 10

  attr_reader :from, :to

  def initialize(from: Date.yesterday.beginning_of_day, to: Date.yesterday.end_of_day)
    @from = from
    @to = to
  end

  def title = I18n.t("notification_digest.title", date: (I18n.l(from.to_date, format: :long)))

  def activities = @activities ||= Activity.recent.where(created_at: from..to).includes(:user, :server).to_a

  def counts = %i[critical warning info].index_with { |severity| activities.count { |activity| activity.severity == severity } }

  def summary = @summary ||= FleetSummary.new(Server.includes(:inventory_snapshots))

  def lines
    lines = [ I18n.t("notification_digest.fleet", online: summary.online, total: summary.total, to_watch: summary.to_watch, critical: summary.critical, updates: I18n.t("notification_digest.security_updates", count: summary.security_updates)),
              I18n.t("notification_digest.activity", events: I18n.t("notification_digest.events", count: activities.size), critical: counts[:critical], warning: counts[:warning]) ]
    # The servers' own packages, then their Docker images (fixed by updating the image).
    if (cves = ServerVulnerability.host.distinct.count(:cve)).positive?
      lines << I18n.t("notification_digest.vulnerabilities", **vulnerability_counts(ServerVulnerability.host), cves: cves,
                                                             servers: I18n.t("count.servers", count: ServerVulnerability.host.distinct.count(:server_id)))
    end
    if (cves = ServerVulnerability.images.distinct.count(:cve)).positive?
      lines << I18n.t("notification_digest.image_vulnerabilities", **vulnerability_counts(ServerVulnerability.images), cves: cves,
                                                                   images: I18n.t("count.docker_images", count: ServerVulnerability.images.distinct.count(:image)))
    end
    highlights = activities.reject { |activity| activity.severity == :info }.first(HIGHLIGHTS)
    lines += highlights.map { |activity| "- #{activity.label} : #{activity.summary}" }
    lines << I18n.t("notification_digest.nothing") if activities.empty?
    lines
  end

  def vulnerability_counts(scope)
    { fixable: scope.fixable.distinct.count(:cve), serious: scope.fixable.at_least("high").distinct.count(:cve) }
  end
end
