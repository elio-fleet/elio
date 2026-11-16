# Docker of a server, read-only (docker group or root): containers with their
# state, health check, restarts and resources, what they reach of the host
# (privileged, Docker socket, mounts, networks, published ports), images
# (tags, digests, age, size, used or not), disk usage, and the
# vulnerabilities of the images: with Trivy or Grype when the server has one,
# otherwise from the Debian / Ubuntu packages of the image (copied out of one
# of its containers) matched by Elio with the vulnerability feeds.
#
# Scans are kept per image ID (data["scans"]): Trivy / Grype at most once a
# day per image, Elio's own matching again only after an update of the feed;
# at most MAX_SCANS images per collection. An image ID is the same on every
# server that pulled it: a fresh scan of another server is copied, with its
# rows, instead of scanning again ("shared_from"). The disk usage
# (`docker system df`, slow on big hosts) is read every DF_EVERY.
class Inventory::Collectors::Docker < Inventory::Collector
  MAX_SCANS = 10
  SCAN_COMMANDS = { "trivy" => "inventory.trivy_scan", "grype" => "inventory.grype_scan" }.freeze
  SCAN_EVERY = 1.day
  # A container restarting on its own this often has a problem: at least
  # LOOP_RESTARTS restarts since the previous collection (all of them on the
  # first one), and up for less than LOOP_UPTIME (a loop never stays up). One
  # that restarted at boot while waiting for its database, then stays up, is
  # not looping.
  LOOP_RESTARTS = 3
  LOOP_UPTIME = 2.minutes
  # Just after the host booted, containers are still starting (restarting
  # while their database is not up, health check not passed yet): no loop
  # and no unhealthy container during this time (Inventory::DockerStatus).
  BOOT_GRACE = 10.minutes
  STOPPED_LONG = 7.days
  DF_EVERY = 6.hours
  # Host addresses of a published port meaning every interface.
  ALL_INTERFACES = [ "", "0.0.0.0", "::" ].freeze
  DOCKER_SOCKET = %r{(\A|/)docker\.sock\z}
  ZERO_TIME = "0001-01-01"
  UNITS = { "b" => 1, "kb" => 1e3, "mb" => 1e6, "gb" => 1e9, "tb" => 1e12, "kib" => 1024, "mib" => 1024**2, "gib" => 1024**3, "tib" => 1024**4 }.freeze

  def collect
    result = run("inventory.docker")
    sections = self.class.sections(result.stdout)
    access = sections["access"].strip
    return unsupported(I18n.t("inventory.collectors.docker.not_installed")) if access == "absent"
    unless access.match?(/\A\d+\.\d+/)
      message = docker_failure(access, I18n.t("inventory.collectors.docker.unreadable", error: access.presence&.truncate(120) || I18n.t("inventory.collectors.docker.no_answer")))
      return partial({ "docker" => "unreadable", "containers" => [], "images" => [] }, message)
    end

    data = self.class.parse(sections, previous: previous).merge("docker" => "ok", "version" => access)
    scan_images(data)
    read_disk(data)
    failed = data["scans"].values.select { |scan| !scan["kept"] && scan["error"].present? && scan["method"].in?(SCAN_COMMANDS.keys) }
    return partial(data, I18n.t("inventory.collectors.docker.scan_failed", count: failed.size, error: failed.first["error"].truncate(160))) if failed.any?

    ok(data)
  end

  def self.parse(sections, now: Time.current, previous: nil)
    stats = parse_stats(sections["stats"])
    restarts = Array(previous&.dig("containers")).to_h { |container| [ container["id"], container["restarts"].to_i ] }
    booted_at = booted_at(sections["uptime"], now)
    containers = parse_containers(sections["containers"], now: now, previous_restarts: restarts, starting_up: starting_up?(booted_at, now))
      .map { |container| container.merge(stats.fetch(container["id"], {})) }
    used = containers.map { |container| container["image_id"] }.to_set
    images = parse_images(sections["images"]).map { |image| image.merge("used" => used.include?(image["id"])) }
    { "containers" => containers, "images" => images, "scanner" => sections["scanners"].split.first, "booted_at" => booted_at&.utc&.iso8601 }.compact
  end

  # "12345.67 23456.78" (/proc/uptime) → the boot time, nil when unread.
  def self.booted_at(text, now)
    seconds = text.to_s.split.first
    now - seconds.to_f.round if seconds&.match?(/\A\d+(\.\d+)?\z/)
  end

  # Whether the host booted less than BOOT_GRACE before `at`.
  def self.starting_up?(booted_at, at) = booted_at.present? && booted_at > at - BOOT_GRACE

  # The vulnerability rows are not kept in the snapshot (ServerVulnerability).
  def self.snapshot_data(data) = data.except("image_vulnerabilities")

  # A compose label, nil when absent: Docker 26 prints "<no value>" for a
  # missing key of `index .Config.Labels` (older versions print nothing).
  def self.label(value) = (value.presence unless value == "<no value>")

  # "<id>\t/<name>\t<image>\t<image id>\t<state>\t<restarts>\t<health>\t<started>\t<finished>\t<exit>\t<policy>\t<created>\t<project>\t<service>
  #  \t<privileged>\t<mounts JSON>\t<networks>\t<ports JSON>" (the last four are missing from older snapshots' outputs)
  # (`starting_up`: the host just booted, no container is looping yet).
  def self.parse_containers(text, now:, previous_restarts: {}, starting_up: false)
    text.to_s.lines.filter_map do |line|
      id, name, image, image_id, state, restarts, health, started, finished, exit_code, policy, created, project, service,
        privileged, mounts, networks, ports = line.chomp.split("\t", -1)
      next if name.blank? || image_id.blank?

      started_at, finished_at = time(started), time(finished)
      container = { "id" => id.first(12), "name" => name.delete_prefix("/"), "image" => image, "image_id" => image_id, "state" => state,
                    "restarts" => restarts.to_i, "health" => health.presence, "started_at" => started_at&.iso8601, "finished_at" => finished_at&.iso8601,
                    "exit_code" => exit_code.to_i, "restart_policy" => policy.presence, "created_at" => time(created)&.iso8601,
                    "project" => label(project), "service" => label(service) }.compact
      container.merge!(host_access(privileged, mounts, networks, ports))
      new_restarts = container["restarts"] - previous_restarts.fetch(container["id"], 0)
      container["looping"] = true if !starting_up && (state == "restarting" || (new_restarts >= LOOP_RESTARTS && started_at && started_at > now - LOOP_UPTIME))
      container["stopped_long"] = true if state == "exited" && finished_at && finished_at < now - STOPPED_LONG
      container
    end
  end

  # What a container reaches of the host, only the keys that say something:
  # privileged, Docker socket mounted (both give root on the host), mounts,
  # networks, published ports.
  def self.host_access(privileged, mounts, networks, ports)
    mounts = parse_mounts(mounts)
    socket = mounts.any? { |mount| mount.values_at("source", "destination").any? { |path| path.to_s.match?(DOCKER_SOCKET) } }
    { "privileged" => (true if privileged == "true"), "docker_socket" => (true if socket), "mounts" => mounts.presence,
      "networks" => networks.to_s.split.presence, "ports" => parse_ports(ports).presence }.compact
  end

  # `{{json .Mounts}}` → [{ type, source (volume name or host path), destination, read_only }]
  def self.parse_mounts(json)
    Array(json_value(json)).filter_map do |mount|
      next unless mount.is_a?(Hash) && mount["Destination"].present?

      { "type" => mount["Type"], "source" => (mount["Type"] == "volume" ? mount["Name"] : mount["Source"]).presence,
        "destination" => mount["Destination"], "read_only" => (true if mount["RW"] == false) }.compact
    end
  end

  # `{{json .NetworkSettings.Ports}}` ({"80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}], "443/tcp": null})
  # → the published ones: [{ address, port, target, exposure }], exposure "all"
  # (every interface), "loopback" (the machine only) or "address" (one
  # address). The IPv4 and IPv6 bindings of a port count once.
  def self.parse_ports(json)
    bindings = json_value(json)
    return [] unless bindings.is_a?(Hash)

    ports = bindings.flat_map do |target, list|
      Array(list).filter_map do |binding|
        next unless binding.is_a?(Hash) && binding["HostPort"].present?

        address = binding["HostIp"].to_s
        { "address" => address.presence || "0.0.0.0", "port" => binding["HostPort"].to_i, "target" => target, "exposure" => exposure(address) }
      end
    end
    ports.uniq { |port| port.values_at("port", "target", "exposure") }.sort_by { |port| [ port["port"], port["target"] ] }
  end

  def self.exposure(address)
    if address.in?(ALL_INTERFACES) then "all"
    elsif address.start_with?("127.") || address == "::1" then "loopback"
    else "address"
    end
  end

  def self.json_value(text)
    JSON.parse(text.to_s)
  rescue JSON::ParserError
    nil
  end

  # "<id 64>\t0.15%\t12.5MiB / 1.94GiB\t0.63%" → { id12 => { cpu_percent, memory_bytes, memory_percent } }
  def self.parse_stats(text)
    text.to_s.lines.filter_map do |line|
      id, cpu, memory, memory_percent = line.chomp.split("\t")
      next unless id && cpu

      [ id.first(12), { "cpu_percent" => percent(cpu), "memory_bytes" => bytes(memory.to_s.split("/").first), "memory_percent" => percent(memory_percent) }.compact ]
    end.to_h
  end

  # "sha256:…\t["nginx:1.27"]\t["nginx@sha256:…"]\t2024-10-02T18:31:27Z\t191623458\tlinux/amd64"
  def self.parse_images(text)
    text.to_s.lines.filter_map do |line|
      id, tags, digests, created, size, platform = line.chomp.split("\t")
      next unless id&.start_with?("sha256:")

      tags = json_list(tags).reject { |tag| tag.end_with?(":<none>") }
      { "id" => id, "tags" => tags, "digests" => json_list(digests), "created_at" => time(created)&.iso8601, "size" => size.to_i,
        "platform" => platform.presence }.compact
    end
  end

  # "Images\t12\t5\t2.3GB\t1.1GB (47%)" → { "images" => { total, active, size, reclaimable } }
  def self.parse_df(text)
    text.to_s.lines.filter_map do |line|
      type, total, active, size, reclaimable = line.chomp.split("\t")
      next unless type && size

      [ type.downcase.tr(" ", "_"), { "total" => total.to_i, "active" => active.to_i, "size" => bytes(size), "reclaimable" => bytes(reclaimable.to_s.split.first) } ]
    end.to_h
  end

  def self.time(value)
    return if value.blank? || value.start_with?(ZERO_TIME)

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def self.percent(value) = value.to_s.delete("%").strip.then { |number| number.match?(/\A\d+(\.\d+)?\z/) ? number.to_f : nil }

  def self.bytes(value)
    match = value.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*([a-z]+)\z/i)
    match && UNITS[match[2].downcase] ? (match[1].to_f * UNITS[match[2].downcase]).round : nil
  end

  def self.json_list(value)
    list = JSON.parse(value.to_s)
    list.is_a?(Array) ? list.map(&:to_s) : []
  rescue JSON::ParserError
    []
  end

  # --- Vulnerabilities of the images -----------------------------------------

  # "debian 12": a Trivy / Grype severity → ours.
  SEVERITIES = { "critical" => "critical", "high" => "high", "medium" => "medium", "low" => "low", "negligible" => "low" }.freeze

  # Output of the Trivy template of inventory.trivy_scan: "@@os\t<class>\t<type>\t<target>"
  # before the lines of each result, then "<id>\t<package>\t<installed>\t<fixed>\t<severity>\t<title>".
  # The system comes from the target of the os-pkgs result: "nginx:1.25 (debian 12.2)".
  def self.parse_trivy(text)
    os = nil
    rows = text.to_s.each_line.filter_map do |line|
      fields = line.chomp.split("\t", -1)
      if fields.first == "@@os"
        os ||= (match = fields[3].to_s.match(/\((\w+) ([\w.]+)\)\z/)) && fields[1] == "os-pkgs" && { "id" => match[1], "version_id" => match[2] }
        next
      end
      cve, package, installed, fixed, severity, title = fields
      next if cve.blank? || package.blank?

      { cve: cve, source_package: package, packages: [ package ], installed_version: installed.presence,
        fixed_version: fixed.to_s.split(",").first&.strip.presence, severity: SEVERITIES.fetch(severity.to_s.downcase, "unknown"),
        description: title.to_s.squish.truncate(240).presence }
    end
    [ rows.uniq, os.presence ]
  end

  # Grype JSON: matches[] with vulnerability and artifact (and distro).
  def self.parse_grype(json)
    report = JSON.parse(json)
    rows = Array(report["matches"]).map do |match|
      vulnerability, artifact = match["vulnerability"] || {}, match["artifact"] || {}
      { cve: vulnerability["id"], source_package: artifact["name"], packages: [ artifact["name"] ], installed_version: artifact["version"],
        fixed_version: (Array(vulnerability.dig("fix", "versions")).first if vulnerability.dig("fix", "state") == "fixed"),
        severity: SEVERITIES.fetch(vulnerability["severity"].to_s.downcase, "unknown"), description: vulnerability["description"].to_s.squish.truncate(240).presence }
    end
    distro = report["distro"]
    [ rows, distro && { "id" => distro["name"], "version_id" => distro["version"] } ]
  end

  # /var/lib/dpkg/status paragraphs → installed packages (Vulnerabilities::Matcher::Package).
  def self.parse_dpkg_status(text)
    text.to_s.split(/\n\s*\n/).filter_map do |paragraph|
      fields = paragraph.lines.each_with_object({}) { |line, hash| key, value = line.split(":", 2); hash[key] = value.to_s.strip if value && !line.start_with?(" ") }
      next unless fields["Package"].present? && fields["Version"].present? && fields["Status"].to_s.end_with?(" installed")

      source, source_version = fields["Source"].to_s.match(/\A(\S+)(?:\s+\((.+)\))?\z/)&.captures
      Vulnerabilities::Matcher.package(fields["Package"], fields["Version"], source: source, source_version: source_version, built_using: fields["Built-Using"])
    end
  end

  # Writes the image rows (ServerVulnerability, origin image), image by image:
  # an image whose scan was kept keeps its rows.
  def self.record(server, data, _at)
    return unless data["docker"] == "ok" # unreadable: the rows of the last good collection stay

    scanned = data.fetch("image_vulnerabilities", {})
    server.server_vulnerabilities.images.where.not(image: scanned.values.map { |scan| scan["image"] } + kept_references(data)).delete_all
    scanned.each_value do |scan|
      rows = scan["rows"].map { |row| row.symbolize_keys.merge(server_id: server.id, origin: "image", image: scan["image"], source: scan["source"]) }
      Vulnerabilities::Matcher.replace(server, rows, origin: "image", image: scan["image"], log: scan["log"])
    end
  end

  def self.kept_references(data)
    Array(data["images"]).filter_map { |image| image["reference"] if data.dig("scans", image["id"], "kept") }
  end
  private_class_method :kept_references

  # Following the Docker alerts of the settings.
  def self.changes(previous, data)
    settings = AppSetting.current
    flagged = ->(containers, flag) { Array(containers).select { |container| container[flag] }.map { |container| container["name"] }.to_set }
    unhealthy = ->(containers) { Array(containers).select { |container| container["health"] == "unhealthy" }.map { |container| container["name"] }.to_set }
    (settings.docker_alert_unhealthy ? (unhealthy.(data["containers"]) - unhealthy.(previous["containers"])).sort.map { |name| { kind: :container_unhealthy, data: { container: name } } } : []) +
      (settings.docker_alert_restarts ? (flagged.(data["containers"], "looping") - flagged.(previous["containers"], "looping")).sort.map { |name| { kind: :container_restarting, data: { container: name } } } : [])
  end

  private

  # Scans the images that need it (never scanned, or a result older than
  # SCAN_EVERY with Trivy / Grype; with Elio's own matching, after an update
  # of the feed), the oldest scans first, at most MAX_SCANS per collection; an
  # image freshly scanned on another server is copied from it instead. The
  # others keep their previous scan and rows.
  def scan_images(data)
    previous_scans = previous&.dig("scans") || {}
    data["scans"] = {}
    data["image_vulnerabilities"] = {}
    containers = data["containers"].group_by { |container| container["image_id"] }
    data["images"].each do |image|
      image["reference"] = image["tags"].first || containers.fetch(image["id"], []).first&.dig("image") || image["id"]
      image["os"] = previous_scans.dig(image["id"], "os") if previous_scans.dig(image["id"], "os")
    end

    candidates = data["images"].reject do |image|
      keep?(previous_scans[image["id"]], data["scanner"]) || (data["scanner"].nil? && containers.fetch(image["id"], []).empty?)
    end
    shared = fleet_scans(candidates.map { |image| image["id"] }, data["scanner"])
    scanned = 0
    candidates.sort_by { |image| previous_scans.dig(image["id"], "at").to_s }.each do |image|
      if (copy = copy_scan(image, shared[image["id"]], data))
        data["scans"][image["id"]] = copy
        next
      end
      next if scanned >= MAX_SCANS

      scanned += 1
      data["scans"][image["id"]] = scan(image, containers.fetch(image["id"], []), data)
      break if data["scans"][image["id"]]["session_lost"]
    end
    data["images"].each do |image|
      data["scans"][image["id"]] ||= (previous_scans[image["id"]] || { "method" => "none" }).merge("kept" => previous_scans.key?(image["id"]))
    end
  end

  # Disk usage, read every DF_EVERY (slow on hosts with many images and
  # volumes); in between, when it fails or after a scan that lost the SSH
  # session, the last one is kept with its date.
  def read_disk(data)
    last = previous&.dig("disk_at")
    fresh = last && previous["disk"] && Time.zone.parse(last) > DF_EVERY.ago
    if fresh || data["scans"].each_value.any? { |scan| scan["session_lost"] }
      data.merge!(previous.to_h.slice("disk", "disk_at"))
    else
      data.merge!("disk" => self.class.parse_df(run("inventory.docker_df").stdout), "disk_at" => Time.current.iso8601)
    end
  rescue Inventory::Collector::Error, Ssh::Connection::CommandTimeoutError
    data.merge!(previous.to_h.slice("disk", "disk_at"))
  end

  # A scan of Trivy / Grype is kept for SCAN_EVERY (even a failed one: not
  # minutes of scanning at every collection); one of Elio's own matching
  # while it succeeded and the feed of the image's system has not been
  # updated since.
  def keep?(previous, scanner)
    return false unless previous && previous["at"] && previous["method"] == (scanner || "elio")
    return Time.zone.parse(previous["at"]) > SCAN_EVERY.ago if scanner

    previous["error"].blank? && feed_unchanged?(previous)
  end

  def feed_unchanged?(scan)
    target = Vulnerabilities.target(scan["os"])
    return false unless target

    @feeds ||= {}
    refreshed = @feeds.fetch(target.first) { @feeds[target.first] = VulnerabilityFeed.for(target.first).refreshed_at }
    refreshed.present? && Time.zone.parse(scan["at"]) > refreshed
  end

  # The fresh, successful scans of these images on the other servers, by the
  # same method: { image ID => [scan, server, reference] }, the most recent
  # one of each image.
  def fleet_scans(ids, scanner)
    return {} if ids.empty?

    found = {}
    Inventory::Snapshot.where(category: "docker").where.not(server_id: ssh.server.id)
                       .where("jsonb_exists_any(inventory_snapshots.data->'scans', ARRAY[:ids]::text[])", ids: ids).includes(:server).each do |snapshot|
      references = Array(snapshot.data["images"]).to_h { |image| [ image["id"], image["reference"] ] }
      snapshot.data["scans"].slice(*ids).each do |id, scan|
        next unless references[id] && scan["count"] && scan["error"].blank? && keep?(scan, scanner)
        next if found[id] && found[id].first["at"] >= scan["at"]

        found[id] = [ scan, snapshot.server, references[id] ]
      end
    end
    found
  end

  # Copies the scan of the same image on another server with its rows, or
  # nil when its rows are not all there (scanned here instead).
  def copy_scan(image, shared, data)
    return unless shared

    scan, server, reference = shared
    rows = server.server_vulnerabilities.images.where(image: reference).to_a
    return unless rows.size == scan["count"].to_i

    image["os"] = scan["os"]
    store(data, image, rows.map { |row| shared_row(row) }, rows.first&.source || "image")
    scan.slice("method", "at", "count", "os").merge("shared_from" => server.name)
  end

  # A row of another server as the scanner found it (its severity is set
  # again from the score when the scanner did not rate the CVE).
  def shared_row(row)
    { "cve" => row.cve, "source_package" => row.source_package, "packages" => row.packages, "installed_version" => row.installed_version,
      "fixed_version" => row.fixed_version, "severity" => row.distro_severity || row.severity, "distro_status" => row.distro_status, "description" => row.description }
  end

  def scan(image, users, data)
    if data["scanner"]
      result = run(SCAN_COMMANDS.fetch(data["scanner"]), image: image["reference"])
      return { "method" => data["scanner"], "at" => Time.current.iso8601, "error" => result.stderr.strip.truncate(200).presence || "code #{result.exit_status}" } unless result.success?

      rows, os = data["scanner"] == "trivy" ? self.class.parse_trivy(result.stdout) : self.class.parse_grype(result.stdout)
      image["os"] = os
      store(data, image, rows, os&.dig("id") || "image")
      { "method" => data["scanner"], "at" => Time.current.iso8601, "count" => rows.size, "os" => os }.compact
    else
      container = users.find { |candidate| candidate["state"] == "running" } || users.first
      sections = self.class.sections(run("inventory.docker_image_packages", container: container["id"]).stdout)
      os = Inventory::Collectors::Os.release_summary(sections["os-release"]).presence
      image["os"] = os
      target = Vulnerabilities.target(os)
      return { "method" => "elio", "at" => Time.current.iso8601, "os" => os, "error" => (os ? I18n.t("inventory.collectors.docker.not_covered") : I18n.t("inventory.collectors.docker.unknown_system")) }.compact unless target
      feed = VulnerabilityFeed.for(target.first)
      unless feed.refreshed_at && feed.releases.include?(target.last)
        return { "method" => "elio", "at" => Time.current.iso8601, "os" => os,
                 "error" => I18n.t("inventory.collectors.docker.not_in_feed", target_last: target.last, label: feed.label) }
      end

      rows = Vulnerabilities::Matcher.affected(*target, self.class.parse_dpkg_status(sections["dpkg"]))
      store(data, image, rows.map { |row| row.except(:source) }, target.first)
      { "method" => "elio", "at" => Time.current.iso8601, "count" => rows.size, "os" => os }
    end
  rescue JSON::ParserError
    { "method" => data["scanner"], "at" => Time.current.iso8601, "error" => I18n.t("inventory.collectors.docker.unreadable_report") }
  rescue Inventory::Collector::Error => e
    { "method" => data["scanner"] || "elio", "at" => Time.current.iso8601, "error" => e.message }
  rescue Ssh::Connection::CommandTimeoutError
    { "method" => data["scanner"] || "elio", "at" => Time.current.iso8601, "error" => I18n.t("inventory.collectors.docker.timeout"), "session_lost" => true }
  end

  # Rows to write (record); new serious ones logged, except on the first
  # Docker collection of the server.
  def store(data, image, rows, source)
    data["image_vulnerabilities"][image["id"]] = { "image" => image["reference"], "source" => source, "rows" => rows.map(&:stringify_keys),
                                                   "log" => previous&.dig("scans").present? }
  end
end
