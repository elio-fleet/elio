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
    since && since < max_age_hours.to_f.hours.ago ? :late : :ok
  end
end
