# A source of severity scores for the CVEs of the fleet, in priority order
# (Settings → Vulnérabilités). Built-in ones (NVD bulk feeds, Red Hat and
# CVE.org APIs, EPSS and CISA KEV for exploitation) are created on first
# access; custom ones read a JSON API (path) or an HTML page (CSS selector
# and / or regex) at an URL template with {cve}, at a limited pace.
class ScoreProvider < ApplicationRecord
  # Descriptions: score_provider.builtins.<key>.
  Builtin = Data.define(:key, :name, :category, :page_url) do
    def description = I18n.t("score_provider.builtins.#{key}")
  end

  BUILTINS = [
    Builtin.new("nvd", "NVD (NIST)", "cvss", "https://nvd.nist.gov/vuln/detail/{cve}"),
    Builtin.new("redhat", "Red Hat", "cvss", "https://access.redhat.com/security/cve/{cve}"),
    Builtin.new("cveorg", "CVE.org / CISA", "cvss", "https://www.cve.org/CVERecord?id={cve}"),
    Builtin.new("epss", "EPSS (FIRST)", "exploitation", "https://www.first.org/epss/"),
    Builtin.new("kev", "CISA KEV", "exploitation", "https://www.cisa.gov/known-exploited-vulnerabilities-catalog")
  ].index_by(&:key).freeze

  FORMATS = %w[json html].freeze

  def self.format_label(format) = I18n.t("score_provider.formats.#{format}", default: format.to_s)
  DEFAULTS = { "delay_ms" => 1000, "max_per_run" => 500 }.freeze
  # Pace of the built-in per-CVE APIs (public, no published limit: kept polite).
  BUILTIN_DEFAULTS = { "redhat" => { "delay_ms" => 250, "max_per_run" => 2000 }, "cveorg" => { "delay_ms" => 250, "max_per_run" => 2000 },
                       "nvd" => { "delay_ms" => 6500, "max_per_run" => 200 } }.freeze

  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(enabled: true) }

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, inclusion: { in: BUILTINS.keys + %w[custom] }
  validate :custom_settings_valid, if: :custom?

  # The built-in providers (enabled, in this order) then the custom ones.
  def self.all_providers
    BUILTINS.each_value.with_index do |builtin, index|
      find_or_create_by!(key: builtin.key) { |provider| provider.assign_attributes(name: builtin.name, kind: builtin.key, position: index) }
    end
    ordered.to_a
  end

  def self.cvss = all_providers.select(&:cvss?)

  def builtin = BUILTINS[kind]
  def custom? = kind == "custom"
  def category = custom? ? "cvss" : builtin.category
  def cvss? = category == "cvss"
  def description = custom? ? I18n.t("score_provider.custom_description", fetch: (FORMATS.include?(setting("format")) ? self.class.format_label(setting("format")) : ""), setting: (setting("url_template"))) : builtin.description

  def setting(name) = settings.fetch(name.to_s) { BUILTIN_DEFAULTS.dig(kind, name.to_s) || DEFAULTS[name.to_s] }

  # Page of the CVE at the provider, for people.
  def page_url(cve)
    template = custom? ? setting("page_url_template").presence || setting("url_template") : builtin.page_url
    template.to_s.gsub("{cve}", ERB::Util.url_encode(cve)).then { |url| kind == "redhat" ? url.downcase : url }
  end

  def scores = CveScore.where(provider_key: key)

  # Custom provider fields from the settings form.
  def assign_custom(values)
    values = values.to_h.stringify_keys
    self.name = values["name"].to_s.squish
    self.settings = { "url_template" => values["url_template"].to_s.strip, "page_url_template" => values["page_url_template"].to_s.strip.presence,
                      "format" => values["format"], "json_path" => values["json_path"].to_s.strip.presence,
                      "css_selector" => values["css_selector"].to_s.strip.presence, "regex" => values["regex"].to_s.strip.presence,
                      "delay_ms" => values["delay_ms"].presence&.to_i || DEFAULTS["delay_ms"],
                      "max_per_run" => values["max_per_run"].presence&.to_i || DEFAULTS["max_per_run"] }.compact
    self
  end

  private

  def custom_settings_valid
    url = setting("url_template").to_s
    errors.add(:base, "L'adresse doit commencer par https:// et contenir {cve}") unless url.start_with?("https://") && url.include?("{cve}")
    errors.add(:base, I18n.t("score_provider.unknown_format")) unless FORMATS.include?(setting("format"))
    errors.add(:base, I18n.t("score_provider.json_path_required")) if setting("format") == "json" && setting("json_path").blank?
    errors.add(:base, I18n.t("score_provider.selector_required")) if setting("format") == "html" && setting("css_selector").blank? && setting("regex").blank?
    begin
      Regexp.new(setting("regex"), timeout: 1) if setting("regex")
    rescue RegexpError => e
      errors.add(:base, I18n.t("score_provider.invalid_regex", message: e.message))
    end
    errors.add(:base, I18n.t("score_provider.delay_too_short")) if setting("delay_ms").to_i < 200
    errors.add(:base, I18n.t("score_provider.max_per_run_range")) unless (1..5000).cover?(setting("max_per_run").to_i)
  end
end
