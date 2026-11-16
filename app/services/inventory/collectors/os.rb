# System of a server: distribution (/etc/os-release), kernel (and the newest
# installed one), architecture, host name, virtualization, boot time, CPUs
# (model, physical cores, sockets), memory, time zone, machine maker and model
# (DMI) and Proxmox VE host. One read-only command, its sections separated by
# "@@elio <name>" lines.
class Inventory::Collectors::Os < Inventory::Collector
  # A boot time that moves by less than this is the same boot (rounding of /proc/uptime).
  REBOOT_TOLERANCE = 5.minutes
  # systemd-detect-virt values of a container: the DMI fields it reads are its host's.
  CONTAINERS = %w[openvz lxc lxc-libvirt systemd-nspawn docker podman rkt wsl proot pouch].freeze
  # DMI values firmwares leave when the maker filled nothing in.
  DMI_PLACEHOLDERS = /\A(to be filled by o\.?e\.?m\.?|system manufacturer|system product name|default string|not specified|not applicable|none|o\.?e\.?m\.?|unknown|\s*)\z/i

  def collect
    result = run("inventory.os")
    raise Error, I18n.t("inventory.collectors.os.failed", exit_status: (result.stderr.strip.presence || "code #{result.exit_status}")) if result.stdout.blank?

    ok(self.class.parse(result.stdout))
  end

  def self.parse(output, now: Time.current)
    sections = sections(output)
    release = parse_os_release(sections["os-release"])
    kernel, arch = parse_uname(sections["uname"])
    uptime = sections["uptime"].to_s.split.first&.to_f&.round
    cpuinfo = key_values(sections["cpuinfo"])
    hypervisor, hypervisor_version = sections["hypervisor"].to_s.split(" ", 2).map(&:strip)

    {
      "name" => release["PRETTY_NAME"].presence || [ release["NAME"], release["VERSION"] ].compact.join(" ").presence || "Inconnu",
      "id" => release["ID"],
      "id_like" => release["ID_LIKE"],
      "version_id" => release["VERSION_ID"],
      "codename" => release["VERSION_CODENAME"].presence || release["UBUNTU_CODENAME"],
      "kernel" => kernel,
      "kernel_latest" => parse_kernel_latest(sections["kernel_latest"], kernel),
      "arch" => arch,
      "hostname" => sections["hostname"].to_s.strip.presence,
      "virtualization" => parse_virt(sections["virt"]),
      "booted_at" => (uptime && (now - uptime).utc.iso8601),
      "cpus" => sections["cpus"].to_s[/\d+/]&.to_i,
      "cpu_model" => cpuinfo["model"]&.squish.presence,
      "cpu_cores" => positive(cpuinfo["cores"]),
      "cpu_sockets" => positive(cpuinfo["sockets"]),
      "memory_bytes" => sections["meminfo"].to_s[/MemTotal:\s+(\d+)\s*kB/, 1]&.to_i&.*(1024),
      "timezone" => sections["timezone"].to_s.strip.presence,
      "hardware" => parse_hardware(key_values(sections["dmi"])),
      "hypervisor" => hypervisor.presence,
      "hypervisor_version" => hypervisor_version.presence
    }.compact
  end

  def self.changes(previous, data)
    changes = []
    if previous["version_id"].present? && data["version_id"].present? && previous["version_id"] != data["version_id"]
      changes << { kind: :os_upgraded, data: { from: previous["name"], to: data["name"] } }
    end
    if previous["booted_at"] && data["booted_at"] && Time.iso8601(data["booted_at"]) - Time.iso8601(previous["booted_at"]) > REBOOT_TOLERANCE
      changes << { kind: :server_rebooted, data: { booted_at: data["booted_at"] } }
    end
    changes
  end

  def self.container?(virtualization) = CONTAINERS.include?(virtualization)

  def self.server_attributes(data)
    { os_name: data["name"], os_id: data["id"], os_version: data["version_id"] }
  end


  # KEY=value lines, values optionally quoted (os-release(5)).
  def self.parse_os_release(text)
    text.to_s.each_line.filter_map do |line|
      key, value = line.strip.split("=", 2)
      next unless value && key.match?(/\A[A-Z_]+\z/)

      [ key, value.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'").gsub('\\"', '"') ]
    end.to_h
  end

  # os-release of a Docker image: the keys Vulnerabilities.target needs.
  def self.release_summary(text)
    release = parse_os_release(text)
    { "id" => release["ID"], "codename" => release["VERSION_CODENAME"].presence || release["UBUNTU_CODENAME"], "version_id" => release["VERSION_ID"],
      "name" => release["PRETTY_NAME"] }.compact_blank
  end

  # "Linux 6.1.0-25-amd64 x86_64"
  def self.parse_uname(text)
    _system, kernel, arch = text.to_s.split
    [ kernel, arch ]
  end
  private_class_method :parse_uname

  # "key=value" lines (cpuinfo and dmi sections).
  def self.key_values(text)
    text.to_s.each_line.filter_map { |line| line.chomp.split("=", 2) if line.include?("=") }.to_h
  end
  private_class_method :key_values

  def self.positive(value) = value.to_s[/\A\d+\z/]&.to_i&.nonzero?
  private_class_method :positive

  # The newest of the running kernel and those installed in /boot (sort -V on
  # the server): kept only when it is not the running one, i.e. a newer kernel
  # waits for a reboot.
  def self.parse_kernel_latest(text, kernel)
    latest = text.to_s.strip.presence
    latest if latest && kernel && latest != kernel
  end
  private_class_method :parse_kernel_latest

  # "Dell Inc." + "PowerEdge R640" → "Dell Inc. PowerEdge R640"; the maker is
  # left out when the model already starts with it ("VMware Virtual Platform").
  def self.parse_hardware(dmi)
    vendor, product = dmi.values_at("sys_vendor", "product_name").map { |value| value.to_s.squish.presence unless value.to_s.match?(DMI_PLACEHOLDERS) }
    return vendor unless product
    return product if vendor.nil? || product.downcase.start_with?(vendor.split.first.delete(",").downcase)

    "#{vendor} #{product}"
  end
  private_class_method :parse_hardware

  # "kvm", "lxc", "docker"…, or "none" on a physical machine.
  def self.parse_virt(text) = text.to_s.strip.presence
  private_class_method :parse_virt
end
