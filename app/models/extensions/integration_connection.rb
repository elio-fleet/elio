# One connection of an extension that accepts several (its definition has
# `connection_fields`): a Coolify team, another instance… Its own fields,
# secrets and synchronization state; the extension keeps the settings shared
# by all its connections (alerts). What a connection reads belongs to it:
# its tables reference it with ON DELETE CASCADE, so removing it removes
# what it brought.
class IntegrationConnection < ApplicationRecord
  include IntegrationValues

  belongs_to :integration, inverse_of: :connections

  normalizes :name, with: ->(value) { value.squish.presence }
  validates :name, length: { maximum: 80 }
  validate :connection_fields_valid

  delegate :definition, to: :integration

  def fields = definition.connection_fields

  # The name given by hand, else what the definition reads (a Coolify team),
  # else "Connection #12".
  def label = name.presence || definition.connection_label(self).presence || I18n.t("integration_connection.default_label", id: id)

  # Heading the connections are grouped under (a Coolify instance), or nil.
  def group = definition.connection_group(self)

  # Synchronizes this connection: remembers the date, or the error (logged
  # once until it is fixed). Returns the summary; raises Integrations::Error.
  def sync!
    result = definition.sync_connection(self)
    update!(last_synced_at: Time.current, last_error: nil)
    result
  rescue Integrations::Error => e
    Activity.record!(:integration_sync_failed, user: nil, integration: integration.kind, integration_label: "#{integration.label} · #{label}", error: e.message) if last_error.nil?
    update_columns(last_error: e.message, updated_at: Time.current)
    raise
  end

  private

  def connection_fields_valid
    validate_urls
    validate_required("integration_connection.required")
  end
end
