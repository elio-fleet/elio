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

  def running? = state == "running"
  def stopped? = state.in?(%w[exited stopped])
  def unhealthy? = running? && health == "unhealthy"

  # Domains served (application fqdn, service applications), without the scheme.
  def domains = Array(data["domains"])
end
