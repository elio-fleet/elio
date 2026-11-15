# Health thresholds that apply to a server, each one taken from the first
# place that sets it: the server (Server#health_thresholds), else its groups
# (ServerGroup#health_thresholds, the strictest when several set it), else
# the settings (AppSetting). Inventory::HealthStatus compares the last
# inventory with them, the health card colours its meters with them.
class Inventory::HealthThresholds
  # Keys of a server's or a group's thresholds, each the AppSetting column
  # `health_<key>`. Percentages, except the load (× processors). A blank
  # swap threshold of the settings means the swap is not watched.
  KEYS = %w[disk_warn disk_crit inodes_warn inodes_crit memory_warn memory_crit swap_warn swap_crit load_warn].freeze
  PAIRS = %w[disk inodes memory swap].freeze
  LOAD_RANGE = (0.1..50).freeze
  PERCENT_RANGE = (1..100).freeze

  # Cleans the thresholds of a form ({ "disk_warn" => "85", "load_warn" => "1,5", … }):
  # blanks dropped, numbers as numbers, anything else kept for the validation.
  def self.clean(values)
    values.to_h.stringify_keys.slice(*KEYS).compact_blank.to_h do |key, value|
      number = Float(value.to_s.strip.tr(",", "."), exception: false)
      [ key, number.nil? ? value.to_s : (key == "load_warn" ? number : number.round) ]
    end
  end

  # Errors of a set of thresholds (translation keys of activerecord.errors.messages):
  # out of range, or a warning not below its critical.
  def self.errors(values)
    errors = values.filter_map do |key, value|
      range = key == "load_warn" ? LOAD_RANGE : PERCENT_RANGE
      :health_threshold_range unless value.is_a?(Numeric) && range.cover?(value)
    end
    errors << :health_threshold_order if PAIRS.any? { |pair| below_critical?(values["#{pair}_warn"], values["#{pair}_crit"]) == false }
    errors.uniq
  end

  def self.below_critical?(warn, crit)
    return if !warn.is_a?(Numeric) || !crit.is_a?(Numeric)

    warn < crit
  end

  def initialize(server, settings = AppSetting.current)
    @server = server
    @settings = settings
  end

  KEYS.each { |key| define_method(key) { values[key] } }

  def values
    @values ||= KEYS.to_h { |key| [ key, own(key) || inherited(key) ] }
  end

  # The threshold the server would have without its own (from its groups or
  # the settings): the hint of its form.
  def inherited(key) = groups(key) || @settings.public_send("health_#{key}")

  private

  def own(key) = @server.health_thresholds.to_h[key]

  def groups(key) = @server.server_groups.filter_map { |group| group.health_thresholds.to_h[key] }.min
end
