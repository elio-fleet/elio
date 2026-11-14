# Health of a server: load, memory, swap, disks (space and inodes), reboot
# required, failed systemd units, pending updates (apt simulation) and clock
# synchronization. One read-only command (no root needed), its sections
# separated by "@@elio <name>" lines. Each collection also adds a point to the
# 30-day history (Inventory::HealthSample).
class Inventory::Collectors::Health < Inventory::Collector
  EXCLUDED_FILESYSTEMS = %w[tmpfs devtmpfs overlay squashfs efivarfs ramfs nsfs].freeze

  def collect
    result = run("inventory.health")
    raise Error, I18n.t("inventory.collectors.health.failed", exit_status: (result.stderr.strip.presence || "code #{result.exit_status}")) if result.stdout.blank?

    ok(self.class.parse(result.stdout))
  end

  def self.parse(output)
    sections = sections(output)
    cpus = sections["cpus"].to_s[/\d+/]&.to_i
    load = sections["loadavg"].to_s.split.first(3).map(&:to_f)
    memory = parse_meminfo(sections["meminfo"])
    disks = parse_disks(sections["df"], parse_inodes(sections["inodes"]))

    {
      "load" => load.presence,
      "cpus" => cpus,
      "load_percent" => (percent(load.first, cpus) if load.any? && cpus.to_i.positive?),
      "memory" => memory[:memory],
      "swap" => memory[:swap],
      "disks" => disks,
      "disk_max_percent" => disks.map { |disk| disk["used_percent"] }.compact.max,
      "reboot_required" => sections["reboot"].to_s.strip == "yes",
      "failed_units" => sections["failed"].to_s.lines.filter_map { |line| line.split.first.presence },
      "failed_units_details" => parse_failed_details(sections["failed_details"]).presence,
      "updates" => parse_updates(sections["updates"]),
      "ntp_synchronized" => { "yes" => true, "no" => false }[sections["ntp"].to_s.strip]
    }.compact
  end

  def self.record(server, data, at)
    Inventory::HealthSample.create!(server: server, collected_at: at, load_percent: data["load_percent"],
                                    memory_percent: data.dig("memory", "used_percent"), disk_percent: data["disk_max_percent"])
  end

  # `systemctl show -p Id -p Description -p Result -p StateChangeTimestamp`
  # of the failed units: one block per unit, separated by blank lines. The
  # timestamp is "@<epoch>" (--timestamp=unix, systemd >= 247) or the
  # default "Fri 2026-11-13 17:32:36 UTC".
  def self.parse_failed_details(text)
    text.to_s.split(/\n\s*\n/).filter_map do |block|
      values = block.lines.to_h { |line| line.chomp.split("=", 2) }.compact_blank
      next unless values["Id"]

      { "name" => values["Id"], "description" => values["Description"], "result" => values["Result"], "since" => unit_time(values["StateChangeTimestamp"])&.iso8601 }.compact
    end
  end

  def self.unit_time(value)
    return if value.blank?
    return Time.at(value.delete_prefix("@").to_i).utc if value.start_with?("@")

    Time.parse(value).utc
  rescue ArgumentError
    nil
  end

  def self.parse_meminfo(text)
    values = text.to_s.scan(/^(\w+):\s+(\d+)\s*kB/).to_h { |key, kb| [ key, kb.to_i * 1024 ] }
    memory = if values["MemTotal"].to_i.positive?
      used = values["MemTotal"] - values.fetch("MemAvailable", values["MemTotal"])
      { "total" => values["MemTotal"], "available" => values["MemAvailable"], "used_percent" => percent(used, values["MemTotal"]) }.compact
    end
    swap = if values["SwapTotal"].to_i.positive?
      { "total" => values["SwapTotal"], "used_percent" => percent(values["SwapTotal"] - values.fetch("SwapFree", 0), values["SwapTotal"]) }
    end
    { memory: memory, swap: swap }
  end
  private_class_method :parse_meminfo

  # df -P -T -k: Filesystem Type 1024-blocks Used Available Capacity Mounted-on
  def self.parse_disks(text, inodes)
    text.to_s.lines.drop(1).filter_map do |line|
      device, type, size, used, available, _capacity, *mount = line.split
      next if mount.empty? || size.to_i.zero? || EXCLUDED_FILESYSTEMS.include?(type)

      mount = mount.join(" ")
      { "mount" => mount, "device" => device, "type" => type, "size" => size.to_i * 1024, "used" => used.to_i * 1024,
        "available" => available.to_i * 1024, "used_percent" => percent(used.to_i, used.to_i + available.to_i),
        "inodes_used_percent" => inodes[mount] }.compact
    end.uniq { |disk| disk["mount"] }
  end
  private_class_method :parse_disks

  # df -P -T -i: Filesystem Type Inodes IUsed IFree IUse% Mounted-on ("-" when not applicable)
  def self.parse_inodes(text)
    text.to_s.lines.drop(1).filter_map do |line|
      _device, _type, total, used, _free, _use, *mount = line.split
      next if mount.empty? || total.to_i.zero?

      [ mount.join(" "), percent(used.to_i, total.to_i) ]
    end.to_h
  end
  private_class_method :parse_inodes

  # "Inst openssl [3.0.14-1~deb12u1] (3.0.15-1~deb12u1 Debian-Security:12/stable-security [amd64])".
  # Only the upgrades of installed packages count (they have an "[old version]"),
  # not the new packages an upgrade would pull (a new kernel…), like the packages page.
  def self.parse_updates(text)
    return if text.to_s.strip == "unsupported" || text.nil?

    lines = text.lines.select { |line| line.match?(/\AInst \S+ \[/) }
    { "total" => lines.size, "security" => lines.count { |line| line.match?(/-security\b/i) } }
  end
  private_class_method :parse_updates

  def self.percent(part, total) = total.to_f.positive? ? (part.to_f * 100 / total).round(1) : nil
  private_class_method :percent
end
