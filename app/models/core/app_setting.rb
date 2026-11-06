# Application-wide settings (a single row).
class AppSetting < ApplicationRecord
  include Localized
  localized :default_locale, allow_nil: false

  validates :health_disk_warn, :health_disk_crit, :health_memory_warn, :health_memory_crit,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :health_load_warn, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validate :warning_thresholds_below_critical
  # From which severity a fixable CVE is a critical health reason and an activity ("none": never).
  # Debian rates few issues (most are "not yet assigned"): "any" alerts on every fixable one.
  VULNERABILITY_ALERTS = %w[critical high medium any none].freeze

  def self.vulnerability_alert_options = VULNERABILITY_ALERTS.map { |key| [ I18n.t("app_setting.vulnerability_alerts.#{key}"), key ] }
  validates :vulnerability_alert_severity, inclusion: { in: VULNERABILITY_ALERTS }
  # Colours of the CVSS scores: three bands, each from a score (0 to 10, increasing).
  SCORE_COLORS = %w[green orange red violet blue gray].freeze

  def self.score_color_options = SCORE_COLORS.map { |key| [ I18n.t("app_setting.score_colors.#{key}"), key ] }
  validate :score_bands_valid

  # Colour of a score ("green"…), nil without a score.
  def score_color(score)
    return if score.nil?

    score_bands.sort_by { |band| band["from"].to_f }.reverse.find { |band| score.to_f >= band["from"].to_f }&.dig("color") || score_bands.first["color"]
  end

  # From the settings form: { "0" => { "from" => "0", "color" => "green" }, … }.
  def score_bands_form=(values)
    self.score_bands = values.to_h.values.map { |band| { "from" => band["from"].to_s.tr(",", ".").to_f, "color" => band["color"].to_s } }
  end

  # Instructions of the administrator added at the end of each prompt for an AI.
  PROMPT_KINDS = %w[monitors firewall].freeze
  PROMPT_INSTRUCTIONS_MAX = 2000
  validate :prompt_instructions_valid

  def prompt_instruction(kind) = prompt_instructions[kind.to_s].to_s.strip.presence

  # From the settings form: { "monitors" => "…", "firewall" => "…" }, blanks dropped.
  def prompt_instructions_form=(values)
    self.prompt_instructions = PROMPT_KINDS.to_h { |kind| [ kind, values.to_h[kind].to_s.strip.gsub("\r\n", "\n") ] }.compact_blank
  end

  # "registry user token" lines (ImageRegistry::UpdateCheck.credentials).
  encrypts :docker_registry_credentials

  def self.current = first || create!

  private

  def prompt_instructions_valid
    errors.add(:prompt_instructions, :invalid) unless prompt_instructions.is_a?(Hash) && (prompt_instructions.keys - PROMPT_KINDS).empty?
    too_long = PROMPT_KINDS.select { |kind| prompt_instructions.is_a?(Hash) && prompt_instructions[kind].to_s.size > PROMPT_INSTRUCTIONS_MAX }
    errors.add(:prompt_instructions, :too_long, count: PROMPT_INSTRUCTIONS_MAX) if too_long.any?
  end

  def score_bands_valid
    froms = score_bands.map { |band| band["from"].to_f }
    errors.add(:score_bands, I18n.t("app_setting.three_bands")) unless score_bands.size == 3
    errors.add(:score_bands, I18n.t("app_setting.band_range")) unless froms.first&.zero? && froms == froms.sort && froms.uniq.size == froms.size && froms.all? { |from| from.between?(0, 10) }
    errors.add(:score_bands, I18n.t("app_setting.unknown_color")) unless score_bands.all? { |band| SCORE_COLORS.include?(band["color"]) }
  end

  def warning_thresholds_below_critical
    errors.add(:health_disk_warn, :less_than, count: health_disk_crit) if health_disk_warn.to_i >= health_disk_crit.to_i
    errors.add(:health_memory_warn, :less_than, count: health_memory_crit) if health_memory_warn.to_i >= health_memory_crit.to_i
  end
end
