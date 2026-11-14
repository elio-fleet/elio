# Health of a server: load, memory, swap, disks (space and inodes), reboot
# required, failed systemd units, pending updates (apt simulation), clock
# synchronization and processes killed for lack of memory. One read-only
# command (no root needed), its sections separated by "@@elio <name>" lines.
# Each collection also adds a point to the 30-day history
# (Inventory::HealthSample).
class Inventory::Collectors::Health < Inventory::Collector
  EXCLUDED_FILESYSTEMS = %w[tmpfs devtmpfs overlay squashfs efivarfs ramfs nsfs fuse.lxcfs fuse.snapfuse].freeze
  # Not disks: the files a container runtime mounts from the host's disk
  # (/etc/hosts, /etc/resolv.conf, /dev/termination-log…) and the kernel's
  # own trees. Without this, a container's "fullest disk" was /etc/hosts.
  VIRTUAL_MOUNT_PREFIXES = %w[/etc/ /dev/ /proc/ /sys/ /run/secrets/].freeze
  # The apt simulation is the costly part of the health: it runs again only
  # when the package database or lists changed (their modification times, the
  # "stamp"), or when the last one is older than this.
  UPDATES_MAX_AGE = 6.hours
  # Processes killed for lack of memory are remembered this long (health reason).
  OOM_WINDOW = 24.hours

  def collect
    result = run("inventory.health", updates_stamp: reusable_updates_stamp)
    raise Error, I18n.t("inventory.collectors.health.failed", exit_status: (result.stderr.strip.presence || "code #{result.exit_status}")) if result.stdout.blank?

    ok(self.class.parse(result.stdout, previous: previous))
  end

  # `previous`: data of the last collection, to reuse its pending updates when
  # the server says nothing changed, and to count the new out-of-memory kills.
  def self.parse(output, previous: nil, now: Time.current)
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
      **updates(sections, previous, now),
      "ntp_synchronized" => { "yes" => true, "no" => false }[sections["ntp"].to_s.strip],
      **oom_kills(sections, previous, now)
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
      mount = mount.join(" ")
      next if mount.empty? || size.to_i.zero? || EXCLUDED_FILESYSTEMS.include?(type) || mount.start_with?(*VIRTUAL_MOUNT_PREFIXES)

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

  # The pending updates and when they were computed, with the stamp of the
  # package database they come from; those of the last collection when the
  # server answers "unchanged" (same stamp).
  def self.updates(sections, previous, now)
    stamp = sections["updates_stamp"].strip.presence
    if sections["updates"].strip == "unchanged"
      return {} unless previous&.dig("updates")

      return { "updates" => previous["updates"], "updates_stamp" => stamp, "updates_checked_at" => previous["updates_checked_at"] }
    end

    updates = parse_updates(sections["updates"])
    updates ? { "updates" => updates, "updates_stamp" => stamp, "updates_checked_at" => now.utc.iso8601 } : {}
  end
  private_class_method :updates

  # The kernel counts the processes it killed for lack of memory since boot
  # (/proc/vmstat oom_kill, Linux >= 4.13, readable without root). The new
  # kills since the last collection (all of them after a reboot: another boot
  # id) are kept as events for OOM_WINDOW. None on the first collection: the
  # kills counted then may be old.
  def self.oom_kills(sections, previous, now)
    count = sections["oom_kill"][/\A\s*(\d+)/, 1]&.to_i
    return {} unless count

    boot_id = sections["boot_id"].strip.presence
    events = Array(previous&.dig("oom_kill_events")).select { |event| recent_oom_kill?(event, now) }
    if previous&.key?("oom_kills")
      same_boot = previous["boot_id"] == boot_id && count >= previous["oom_kills"].to_i
      killed = same_boot ? count - previous["oom_kills"].to_i : count
      events += [ { "at" => now.utc.iso8601, "count" => killed } ] if killed.positive?
    end
    { "oom_kills" => count, "boot_id" => boot_id, "oom_kill_events" => events.presence }
  end
  private_class_method :oom_kills

  # Whether an out-of-memory kill event ({ "at", "count" }) is within OOM_WINDOW of `now`.
  def self.recent_oom_kill?(event, now)
    Time.iso8601(event["at"].to_s) > now - OOM_WINDOW
  rescue ArgumentError
    false
  end
  private_class_method :recent_oom_kill?

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

  private

  # The stamp of the last apt simulation when it is recent enough to be
  # reused, "" otherwise (the server then runs it again).
  def reusable_updates_stamp
    return "" unless previous&.dig("updates") && previous["updates_stamp"].present?

    Time.iso8601(previous["updates_checked_at"].to_s) > UPDATES_MAX_AGE.ago ? previous["updates_stamp"] : ""
  rescue ArgumentError
    ""
  end
end
