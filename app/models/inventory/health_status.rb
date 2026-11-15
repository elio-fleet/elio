# Health state of a server from its last inventory and the thresholds of
# AppSetting: ok, warn or crit with the reasons, or unknown before any health
# collection. Unreachability is shown on top of it (Server#health_state).
class Inventory::HealthStatus
  # A reason is stored as its translation key and parameters (servers.health_reasons,
  # activities), and written in the reader's language when shown. `percent`,
  # `load` and `count` parameters are formatted by the language's rules.
  Reason = Data.define(:tone, :key, :params) do
    def initialize(tone:, key:, params: {}) = super(tone: tone, key: key, params: params.stringify_keys)

    def text = Inventory::HealthStatus.text(to_h)

    def to_h = { "tone" => tone, "key" => key, "params" => params }
  end
  Result = Data.define(:state, :reasons)

  # The text of a stored reason ({ "key", "params" }), or of an older one ({ "text" }).
  def self.text(reason)
    return reason.to_s unless reason.is_a?(Hash)
    return reason["text"].to_s unless reason["key"]

    params = (reason["params"] || {}).to_h do |name, value|
      # A `*_key` parameter is a translation key, translated when shown.
      name.to_s.end_with?("_key") ? [ name.to_s.delete_suffix("_key").to_sym, I18n.t(value) ] : [ name.to_sym, format_param(name.to_s, value) ]
    end
    params[:count] = reason.dig("params", "count") if reason.dig("params", "count")
    I18n.t(reason["key"], **params)
  end

  def self.format_param(name, value)
    case name
    when "percent" then ActiveSupport::NumberHelper.number_to_percentage(value, precision: 0, locale: I18n.locale)
    when "ratio" then ActiveSupport::NumberHelper.number_to_percentage(value, precision: 2, locale: I18n.locale)
    when "load" then ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1, strip_insignificant_zeros: true, locale: I18n.locale)
    when "names" then Array(value).to_sentence(locale: I18n.locale)
    when "first_names" then Array(value).join(", ")
    else value
    end
  end

  # Parameters that measure a problem rather than name it: a disk going from
  # 91 to 92 % is the same problem, a second failed service is a new one.
  MEASURES = %w[percent ratio load count].freeze
  # Parameters kept only to compare two readings, never shown: every failed
  # unit, when the text names only the first ones.
  DETAILS = %w[names_all].freeze
  FAILED_UNITS_KEYS = %w[health.service_failed health.units_failed health.units_failed_more].freeze

  # The stored reasons of `current` that were not in `previous`, or that went
  # from warn to crit (Server#refresh_health! logs them). Failed units are one
  # problem whatever their number: new only when a unit fails that had not
  # (a unit that recovers changes the text, not the problems).
  def self.new_reasons(previous, current)
    tones = Array(previous).to_h { |reason| [ identity(reason), reason["tone"] ] }
    failed_before = Array(previous).select { |reason| failed_units?(reason) }.flat_map { |reason| failed_unit_names(reason) }
    Array(current).select do |reason|
      next (failed_unit_names(reason) - failed_before).any? if failed_units?(reason) && failed_before.any?

      tone = tones[identity(reason)]
      tone.nil? || (reason["tone"] == "crit" && tone != "crit")
    end
  end

  def self.identity(reason)
    return reason.to_s unless reason.is_a?(Hash)

    [ reason["key"] || reason["text"], (reason["params"] || {}).to_h.except(*MEASURES, *DETAILS) ]
  end

  def self.failed_units?(reason) = reason.is_a?(Hash) && FAILED_UNITS_KEYS.include?(reason["key"])

  # Every unit a failed-units reason names (only the first ones in a reason
  # stored before `names_all`).
  def self.failed_unit_names(reason)
    params = reason["params"] || {}
    Array(params["names_all"]).presence || [ params["name"], *params["names"], *params["first_names"] ].compact
  end

  def self.reason(tone, key, **params) = Reason.new(tone: tone, key: key.to_s.include?(".") ? key.to_s : "health.#{key}", params: params)

  def self.evaluate(server, settings: AppSetting.current) = new(server, settings).evaluate

  # Version of the rules that compute the reasons: raise it when a reason is
  # added, removed or stored differently. After an upgrade, the first tick of
  # RunDueAutomationsJob computes the health of every server again (with the
  # whole schema of the release, unlike a migration that runs before the
  # following ones).
  # 2: Docker (containers, images and their CVEs) moved to Inventory::DockerStatus.
  # 3: no "OVH firewall disabled" reason for IPv6 blocks (OVH has no firewall for IPv6).
  # 4: Coolify backups (integrations.coolify.health.*).
  # 5: failed units named (health.units_failed / units_failed_more).
  # 6: processes killed for lack of memory in the last 24 hours (health.oom_kills).
  # 7: every failed unit kept with the reason that names only the first ones (names_all).
  VERSION = 7

  def self.refresh_outdated!
    setting = AppSetting.current
    return if setting.health_version >= VERSION

    AdvisoryLock.try("health_version") do
      Server.find_each { |server| server.refresh_health!(new_reasons: false) }
      setting.update_columns(health_version: VERSION)
    end
  end

  def initialize(server, settings)
    @server = server
    @settings = settings
    @health = server.inventory("health")
    @os = server.inventory("os")
  end

  def evaluate
    reasons = [ *access_reasons, *disk_reasons, *memory_reasons, *load_reasons, *system_reasons, *scheduled_task_reasons, *vulnerability_reasons, *port_reasons, *Integration.health_reasons(@server) ]
    reasons = reasons.sort_by { |reason| reason.tone == "crit" ? 0 : 1 }
    state = if reasons.any? { |reason| reason.tone == "crit" } then "crit"
    elsif reasons.any? then "warn"
    elsif @health&.collected? then "ok"
    else "unknown"
    end
    Result.new(state: state, reasons: reasons)
  end

  private

  def data = @health&.collected? ? @health.data : {}

  def access_reasons
    @server.ssh_ok == false ? [ self.class.reason("crit", :key_refused) ] : []
  end

  def disk_reasons
    Array(data["disks"]).flat_map do |disk|
      [ threshold_reason(:disk, disk["used_percent"], @settings.health_disk_warn, @settings.health_disk_crit, mount: disk["mount"]),
        threshold_reason(:inodes, disk["inodes_used_percent"], @settings.health_disk_warn, @settings.health_disk_crit, mount: disk["mount"]) ].compact
    end
  end

  def memory_reasons
    [ threshold_reason(:memory, data.dig("memory", "used_percent"), @settings.health_memory_warn, @settings.health_memory_crit) ].compact
  end

  def load_reasons
    load, cpus = data["load"]&.first, data["cpus"]
    return [] unless load && cpus.to_i.positive? && load >= cpus * @settings.health_load_warn.to_f

    [ self.class.reason("warn", :load, load: load.round(1), count: cpus) ]
  end

  def system_reasons
    reasons = []
    reasons << self.class.reason("warn", :reboot_required) if data["reboot_required"]
    reasons << failed_units_reason(Array(data["failed_units"])) if Array(data["failed_units"]).any?
    reasons << self.class.reason("warn", :clock) if data["ntp_synchronized"] == false
    reasons << self.class.reason("warn", :oom_kills, count: oom_kills) if oom_kills.positive?
    if @os&.collected? && Inventory::EndOfLife.status(@os.data["id"], @os.data["version_id"]).ended?
      reasons << self.class.reason("warn", :unsupported, name: @os.data["name"])
    end
    reasons
  end

  # Processes the kernel killed for lack of memory in the last
  # Inventory::Collectors::Health::OOM_WINDOW (events kept by the collector).
  def oom_kills
    window = Inventory::Collectors::Health::OOM_WINDOW.ago
    Array(data["oom_kill_events"]).sum { |event| Time.zone.parse(event["at"].to_s)&.after?(window) ? event["count"].to_i : 0 }
  end

  # The failed units by name ("nginx", "mnt-backup.mount"): all of them up to
  # FAILED_UNITS_NAMED, else the first ones and how many more.
  FAILED_UNITS_NAMED = 3

  def failed_units_reason(units)
    names = units.map { |unit| unit.delete_suffix(".service") }
    return self.class.reason("warn", :service_failed, name: names.first) if names.one?
    return self.class.reason("warn", :units_failed, names: names) if names.size <= FAILED_UNITS_NAMED

    self.class.reason("warn", :units_failed_more, first_names: names.first(FAILED_UNITS_NAMED - 1), count: names.size - (FAILED_UNITS_NAMED - 1), names_all: names)
  end

  def scheduled_task_reasons
    tasks = @server.inventory("scheduled_tasks")
    timers = tasks&.collected? ? Array(tasks.data["timers"]) : []
    [ [ timers.select { |timer| timer["failed"] }, "failed" ], [ timers.select { |timer| timer["late"] && !timer["failed"] }, "late" ] ].filter_map do |list, state|
      next if list.empty?

      list.one? ? self.class.reason("warn", :"timer_#{state}", name: list.first["name"].delete_suffix(".timer")) : self.class.reason("warn", :"timers_#{state}", count: list.size)
    end
  end

  # Fixable CVEs of the server's own packages from the alert severity of the
  # settings (those of its Docker images: Inventory::DockerStatus).
  def vulnerability_reasons
    minimum = @settings.vulnerability_alert_severity
    return [] if minimum == "none"

    cves = @server.server_vulnerabilities.host.fixable.at_least(minimum).distinct.pluck(:cve)
    return [] if cves.empty?

    [ cves.one? ? self.class.reason("crit", :vulnerability, cve: cves.first) : self.class.reason("crit", :vulnerabilities, count: cves.size) ]
  end

  def port_reasons
    unexpected = Inventory::PortAnalysis.new(@server).unexpected_ports
    return [] if unexpected.empty?

    [ unexpected.one? ? self.class.reason("warn", :port_unexpected, port: unexpected.first.key) : self.class.reason("warn", :ports_unexpected, count: unexpected.size, ports: unexpected.map(&:key).first(3).join(", ")) ]
  end

  # The percentage is formatted by the language ("83 %" with a non-breaking
  # space in French, so that it never splits at the end of a line).
  def threshold_reason(key, value, warn, crit, **params)
    return unless value
    return self.class.reason("crit", key, percent: value.round, **params) if value >= crit

    self.class.reason("warn", key, percent: value.round, **params) if value >= warn
  end
end
