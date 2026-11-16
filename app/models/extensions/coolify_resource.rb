# Something read from Coolify (see Integrations::Coolify) by one connection:
# a Coolify server, attached to the server of the fleet it is, or a resource
# running on it (application, service, standalone database), attached to
# the same server.
class CoolifyResource < ApplicationRecord
  KINDS = %w[server application service database].freeze # labels: coolify_resource.kinds.*
  RESOURCE_KINDS = %w[application service database].freeze

  belongs_to :connection, class_name: "IntegrationConnection", foreign_key: :integration_connection_id, inverse_of: false
  belongs_to :server, optional: true

  scope :servers, -> { where(kind: "server") }
  scope :resources, -> { where(kind: RESOURCE_KINDS) }
  scope :attached, -> { where.not(server_id: nil) }
  scope :ordered, -> { order(:name, :id) }

  # The resource behind a container ({ "name", "project" }) among `resources`:
  # Coolify puts the resource's uuid in the container name ("<uuid>-<timestamp>",
  # "<uuid>", "<part>-<service uuid>") or uses it as the Compose project.
  def self.for_container(resources, container)
    values = [ container["name"], container["project"] ].compact
    resources.find { |resource| RESOURCE_KINDS.include?(resource.kind) && values.any? { |value| value.include?(resource.uuid) } }
  end

  def kind_label = I18n.t("coolify_resource.kinds.#{kind}", default: kind.to_s)

  # "running:healthy" → ["running", "healthy"]; health nil when Coolify has none ("exited").
  def state = status.to_s.split(":").first.presence
  def health = status.to_s.split(":")[1].presence

  # Was it running after `time`? Coolify's last_online_at; true when unknown
  # (a resource Coolify never saw online counts as recently stopped).
  def online_since?(time)
    at = data["last_online_at"].presence or return true
    Time.find_zone("UTC").parse(at.to_s) >= time
  rescue ArgumentError
    true
  end

  def running? = state == "running"
  def stopped? = state.in?(%w[exited stopped])
  def unhealthy? = running? && health == "unhealthy"

  # Domains served (application fqdn, service applications), without the scheme.
  def domains = Array(data["domains"])

  # The databases inside a service (Integrations::Coolify::Fetch#service_database): { "name", "engine", "image", "status", "public", "public_port" }.
  def service_databases = kind == "service" ? Array(data["databases"]) : []

  FINAL_DEPLOYMENTS = %w[finished failed cancelled-by-user].freeze

  # Deployments of an application (Integrations::Coolify::Fetch#deployments), newest first.
  def deployments = Array(data["deployments"])
  def last_deployment = deployments.find { |deployment| FINAL_DEPLOYMENTS.include?(deployment["status"]) }
  def deploy_failed? = last_deployment&.dig("status") == "failed"

  # Backups of a database (Integrations::Coolify::Fetch#backups): the enabled
  # schedules, their executions newest first.
  def backups = Array(data["backups"]).select { |backup| backup["enabled"] }
  def executions = backups.flat_map { |backup| Array(backup["executions"]) }.sort_by { |execution| execution["at"].to_s }.reverse
  def last_success_at = executions.find { |execution| execution["status"] == "success" }&.then { |execution| Time.zone.parse(execution["at"].to_s) }

  # :none (no enabled schedule), :failed (the last finished one failed),
  # :late (no success for max_age_hours, once a schedule has had time to
  # run), :ok — nil for anything else than a database.
  def backup_state(max_age_hours)
    return unless kind == "database"
    return :none if backups.empty?

    finished = executions.reject { |execution| execution["status"] == "running" }
    return :failed if finished.first&.dig("status") == "failed"

    oldest_schedule = backups.filter_map { |backup| backup["created_at"] && Time.zone.parse(backup["created_at"]) }.min
    since = last_success_at || oldest_schedule
    since && since < backup_max_age(max_age_hours).hours.ago ? :late : :ok
  end

  # Coolify's names for its usual schedules (any other frequency is a cron line).
  FREQUENCIES = { "every_minute" => "* * * * *", "hourly" => "0 * * * *", "daily" => "0 0 * * *", "weekly" => "0 0 * * 0",
                  "monthly" => "0 0 1 * *", "yearly" => "0 0 1 1 *" }.freeze
  # Time a backup may take after its scheduled time.
  BACKUP_GRACE_HOURS = 2

  # Hours without a successful backup before it is late: the extension's
  # setting, or longer for a database backed up less often (a weekly backup
  # is not late a day after it ran): the longest gap between two runs of its
  # schedules, plus the time a backup takes.
  def backup_max_age(max_age_hours)
    gaps = backups.filter_map { |backup| self.class.schedule_gap_hours(backup["frequency"]) }
    [ max_age_hours.to_f, *gaps.map { |gap| gap + BACKUP_GRACE_HOURS } ].max
  end

  SCHEDULE_GAPS = Concurrent::Map.new

  # The longest time (hours) between two of the first runs of a schedule
  # (in UTC: no daylight saving shift), nil when it is not a cron line Elio
  # understands. Remembered by frequency: few distinct ones, and the health
  # of every server reads them.
  def self.schedule_gap_hours(frequency)
    line = frequency.to_s.strip
    SCHEDULE_GAPS.compute_if_absent(line) do
      cron = Fugit::Cron.parse("#{FREQUENCIES.fetch(line, line)} UTC")
      if cron
        times = [ cron.next_time(Time.utc(2026, 1, 1)).to_t ]
        40.times { times << cron.next_time(times.last).to_t }
        times.each_cons(2).map { |first, second| second - first }.max / 3600.0
      end
    end
  end

  # The resource's page in its Coolify instance (`suffix`: a sub-page, such as
  # "/backups"), or nil when its path is unknown.
  def coolify_url(suffix = "")
    path = "#{data["coolify_path"] or return}#{suffix}"
    base = connection.value(:url).to_s.chomp("/")
    "#{base}#{path}" if Integration.http_url?(base) && path.match?(%r{\A/[\w/-]+\z})
  end
end
