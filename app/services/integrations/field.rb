# A field of the extension's settings form. `secret`: stored encrypted,
# never sent back to the browser (blank = unchanged). `section`: heading of
# the form (translated by the extension, e.g. "Alerts"; none = the connection
# section).
Integrations::Field = Data.define(:key, :label, :type, :secret, :hint, :default, :required, :options, :section, :placeholder) do
  def initialize(key:, label:, type: :text, secret: false, hint: nil, default: nil, required: false, options: nil, section: nil, placeholder: nil)
    super(key: key.to_s, label:, type:, secret:, hint:, default:, required:, options:, section:, placeholder:)
  end

  def boolean? = type == :boolean

  def section_label = section || I18n.t("integrations.sections.connection")

  # Value from the form (strings) to the stored type.
  def cast(value)
    case type
    when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
    when :number then value.to_s.strip.presence && value.to_s.strip.to_f.then { |number| number == number.to_i ? number.to_i : number }
    when :list then value.is_a?(Array) ? value.compact_blank : value.to_s.split(/[\s,;]+/).compact_blank
    when :checkboxes then Array(value).compact_blank & options.map { |option| option.first.to_s }
    else value.to_s.strip.presence
    end
  end
end
