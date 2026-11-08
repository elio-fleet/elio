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
    else value
    end
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
  VERSION = 3

  def self.refresh_outdated!
    setting = AppSetting.current
    return if setting.health_version >= VERSION

    AdvisoryLock.try("health_version") do
      Server.find_each(&:refresh_health!)
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
    failed = Array(data["failed_units"])
    reasons << (failed.one? ? self.class.reason("warn", :service_failed, name: failed.first.delete_suffix(".service")) : self.class.reason("warn", :services_failed, count: failed.size)) if failed.any?
    reasons << self.class.reason("warn", :clock) if data["ntp_synchronized"] == false
    if @os&.collected? && Inventory::EndOfLife.status(@os.data["id"], @os.data["version_id"]).ended?
      reasons << self.class.reason("warn", :unsupported, name: @os.data["name"])
    end
    reasons
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
