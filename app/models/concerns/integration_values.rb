# The values of a form of extension fields (Integrations::Field): settings in
# a jsonb column, secrets encrypted, read with their default. Shared by an
# extension (Integration, its `fields`) and each of its connections
# (IntegrationConnection, the definition's `connection_fields`). The class
# defines `fields`.
module IntegrationValues
  extend ActiveSupport::Concern

  included do
    serialize :secrets, coder: JSON
    encrypts :secrets
  end

  def secrets = super || {}

  # Value of a field: the secret, the setting, or its default.
  def value(key)
    field = fields.find { |candidate| candidate.key == key.to_s }
    raise ArgumentError, "Unknown field #{key} for #{self.class.name}" unless field

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

  private

  def validate_urls
    fields.select { |field| field.type == :url }.each do |field|
      value = value(field.key)
      next if value.blank? || Integration.http_url?(value)

      errors.add(:base, I18n.t("integration.url_expected", label: field.label))
    end
  end

  def validate_required(message = "integration.required")
    fields.select(&:required).each do |field|
      errors.add(:base, I18n.t(message, label: field.label)) if value(field.key).blank?
    end
  end
end
