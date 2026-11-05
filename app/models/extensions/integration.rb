# An extension connecting Elio to an external service (Uptime Kuma,
# OVHcloud…): read-only, configured by the admins in Settings → Extensions.
# The definition (form fields, sync, tabs…) is a subclass of
# Integrations::Base, found through REGISTRY. A disabled extension leaves no
# trace in the interface; its data is kept for when it is enabled again.
class Integration < ApplicationRecord
  REGISTRY = { "uptime_kuma" => "Integrations::UptimeKuma", "ovh" => "Integrations::Ovh", "technitium" => "Integrations::Technitium" }.freeze

  class << self
    attr_writer :registry

    # kind => definition class name, overridable in tests.
    def registry = @registry ||= REGISTRY.dup

    def definitions = registry.transform_values(&:constantize)

    # Every extension, in registry order (rows created on demand, disabled).
    def all_kinds = registry.keys.map { |kind| find_or_create_by!(kind: kind) }

    def enabled_kinds = where(enabled: true, kind: registry.keys).order(:kind).to_a

    def enabled?(kind) = registry.key?(kind.to_s) && where(kind: kind.to_s, enabled: true).exists?

    def find_enabled(kind) = registry.key?(kind.to_s) ? find_by(kind: kind.to_s, enabled: true) : nil

    # Tabs the enabled extensions add to the server page: [{ key:, label:, count:, integration: }].
    # Tabs of the server page added by the enabled extensions, then the DNS
    # tab when one of them feeds the DNS of the fleet (Dns).
    def server_tabs
      tabs = enabled_kinds.flat_map { |integration| integration.definition.server_tabs.map { |tab| tab.merge(integration: integration) } }
      tabs << { key: "dns", label: I18n.t("dns_records.tab"), count: ->(server) { server.dns_records.size.nonzero? }, partial: "dns_records/server_tab" } if Dns.enabled?
      tabs
    end

    # Sidebar links of the enabled extensions: [{ label:, path:, icon:, controller: }], and the DNS page.
    def sidebar_links
      links = enabled_kinds.flat_map { |integration| integration.definition.sidebar_links }
      links << { label: I18n.t("dns_records.tab"), path: :dns_records_path, icon: :globe, controller: "dns_records" } if Dns.enabled?
      links
    end

    # Health reasons the enabled extensions raise for a server.
    def health_reasons(server) = enabled_kinds.flat_map { |integration| integration.definition.health_reasons(integration, server) }
  end

  def self.http_url?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  serialize :secrets, coder: JSON
  encrypts :secrets

  has_many :links, class_name: "IntegrationLink", dependent: :delete_all

  validates :kind, presence: true, uniqueness: true
  validate :known_kind
  validate :required_fields_when_enabled
  validate :urls_are_http

  def definition = self.class.registry.fetch(kind).constantize

  delegate :label, :description, :icon, :fields, to: :definition

  def secrets = super || {}

  # Value of a field: the secret, the setting, or its default.
  def value(key)
    field = fields.find { |candidate| candidate.key == key.to_s }
    raise ArgumentError, "Unknown field #{key} for #{kind}" unless field

    stored = field.secret ? secrets[field.key] : settings[field.key]
    stored.nil? ? field.default : stored
  end

  def secret?(key) = secrets[key.to_s].present?

  # Values of the settings form (strings). A blank secret keeps the stored one.
  def assign_form(values)
    values = values.to_h.stringify_keys
    new_settings = settings.dup
    new_secrets = secrets.dup
    fields.each do |field|
      next unless values.key?(field.key) || field.boolean? || field.type == :checkboxes

      value = field.cast(values[field.key])
      if field.secret
        new_secrets[field.key] = value if value.present?
      else
        new_settings[field.key] = value
      end
    end
    self.settings = new_settings
    self.secrets = new_secrets
  end

  # Runs the synchronization now (inside a job): remembers the date, or the
  # error (logged once until it is fixed). Returns the summary; raises
  # Integrations::Error when the service cannot be read.
  def sync!
    result = definition.sync(self)
    update!(last_synced_at: Time.current, last_error: nil)
    result
  rescue Integrations::Error => e
    Activity.record!(:integration_sync_failed, user: nil, integration: kind, integration_label: label, error: e.message) if last_error.nil?
    update_columns(last_error: e.message, updated_at: Time.current)
    raise
  end

  # Background synchronization, followed on the "Tâches" page.
  def enqueue_sync!(user: Current.user)
    task = BackgroundTask.enqueue!(kind: "integration", label: I18n.t("integration.sync_label", label: label), servers: [], user: user)
    Integrations::SyncJob.perform_later(self, task)
    task
  end

  # Servers manually attached to (or detached from, server nil) an external resource.
  def manual_links = links.to_h { |link| [ link.external_id, link.server_id ] }

  private

  def known_kind
    errors.add(:kind, :inclusion) unless self.class.registry.key?(kind.to_s)
  end

  def urls_are_http
    return unless self.class.registry.key?(kind.to_s)

    fields.select { |field| field.type == :url }.each do |field|
      value = value(field.key)
      next if value.blank? || self.class.http_url?(value)

      errors.add(:base, "#{field.label} : adresse http(s) attendue (ex. https://uptime.example.com)")
    end
  end

  def required_fields_when_enabled
    return unless enabled? && self.class.registry.key?(kind.to_s)

    fields.select(&:required).each do |field|
      errors.add(:base, I18n.t("integration.required", label: field.label)) if value(field.key).blank?
    end
  end
end
