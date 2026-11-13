# Docker of a server, read-only (docker group or root): containers with their
# state, health check, restarts and resources, images (tags, digests, age,
# size, used or not), disk usage, and the vulnerabilities of the images:
# with Trivy or Grype when the server has one, otherwise from the Debian /
# Ubuntu packages of the image (copied out of one of its containers) matched
# by Elio with the vulnerability feeds.
#
# Scans are kept per image ID (data["scans"]): Trivy / Grype at most once a
# day per image, at most MAX_SCANS images per collection.
class Inventory::Collectors::Docker < Inventory::Collector
  MAX_SCANS = 10
  SCAN_COMMANDS = { "trivy" => "inventory.trivy_scan", "grype" => "inventory.grype_scan" }.freeze
  SCAN_EVERY = 1.day
  # A container restarting on its own this often has a problem.
  LOOP_RESTARTS = 3
  LOOP_WINDOW = 15.minutes
  STOPPED_LONG = 7.days
  ZERO_TIME = "0001-01-01"
  UNITS = { "b" => 1, "kb" => 1e3, "mb" => 1e6, "gb" => 1e9, "tb" => 1e12, "kib" => 1024, "mib" => 1024**2, "gib" => 1024**3, "tib" => 1024**4 }.freeze

  def collect
    result = run("inventory.docker")
    sections = self.class.sections(result.stdout)
    access = sections["access"].strip
    return unsupported(I18n.t("inventory.collectors.docker.not_installed")) if access == "absent"
    unless access.match?(/\A\d+\.\d+/)
      hint = access.match?(/denied/i) ? I18n.t("inventory.collectors.docker.needs_root") : ""
      return partial({ "docker" => "unreadable", "containers" => [], "images" => [] }, I18n.t("inventory.collectors.docker.unreadable", error: access.presence&.truncate(120) || I18n.t("inventory.collectors.docker.no_answer"), hint: hint))
    end

    data = self.class.parse(sections).merge("docker" => "ok", "version" => access)
    scan_images(data)
    ok(data)
  end

  def self.parse(sections, now: Time.current)
    stats = parse_stats(sections["stats"])
    containers = parse_containers(sections["containers"], now: now).map { |container| container.merge(stats.fetch(container["id"], {})) }
    used = containers.map { |container| container["image_id"] }.to_set
    images = parse_images(sections["images"]).map { |image| image.merge("used" => used.include?(image["id"])) }
    { "containers" => containers, "images" => images, "disk" => parse_df(sections["df"]), "scanner" => sections["scanners"].split.first }
  end

  # The vulnerability rows are not kept in the snapshot (ServerVulnerability).
  def self.snapshot_data(data) = data.except("image_vulnerabilities")

  # A compose label, nil when absent: Docker 26 prints "<no value>" for a
  # missing key of `index .Config.Labels` (older versions print nothing).
  def self.label(value) = (value.presence unless value == "<no value>")

  # "<id>\t/<name>\t<image>\t<image id>\t<state>\t<restarts>\t<health>\t<started>\t<finished>\t<exit>\t<policy>\t<created>\t<project>\t<service>"
  def self.parse_containers(text, now:)
    text.to_s.lines.filter_map do |line|
      id, name, image, image_id, state, restarts, health, started, finished, exit_code, policy, created, project, service = line.chomp.split("\t", -1)
      next if name.blank? || image_id.blank?

      started_at, finished_at = time(started), time(finished)
      container = { "id" => id.first(12), "name" => name.delete_prefix("/"), "image" => image, "image_id" => image_id, "state" => state,
                    "restarts" => restarts.to_i, "health" => health.presence, "started_at" => started_at&.iso8601, "finished_at" => finished_at&.iso8601,
                    "exit_code" => exit_code.to_i, "restart_policy" => policy.presence, "created_at" => time(created)&.iso8601,
                    "project" => label(project), "service" => label(service) }.compact
      container["looping"] = true if state == "restarting" || (container["restarts"] >= LOOP_RESTARTS && started_at && started_at > now - LOOP_WINDOW)
      container["stopped_long"] = true if state == "exited" && finished_at && finished_at < now - STOPPED_LONG
      container
    end
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

  # Trivy JSON: Results[].Vulnerabilities[] (and Metadata.OS for the system).
  def self.parse_trivy(json)
    report = JSON.parse(json)
    os = report.dig("Metadata", "OS")
    rows = Array(report["Results"]).flat_map { |result| Array(result["Vulnerabilities"]) }.map do |vulnerability|
      { cve: vulnerability["VulnerabilityID"], source_package: vulnerability["PkgName"], packages: [ vulnerability["PkgName"] ],
        installed_version: vulnerability["InstalledVersion"], fixed_version: vulnerability["FixedVersion"].to_s.split(",").first&.strip.presence,
        severity: SEVERITIES.fetch(vulnerability["Severity"].to_s.downcase, "unknown"),
        description: (vulnerability["Title"].presence || vulnerability["Description"]).to_s.squish.truncate(240).presence }
    end
    [ rows, os && { "id" => os["Family"], "version_id" => os["Name"] } ]
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
  # SCAN_EVERY with Trivy / Grype; at every collection with Elio's own
  # matching, which follows the feed updates), the oldest scans first, at most
  # MAX_SCANS per collection. The others keep their previous scan and rows.
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
    candidates.sort_by { |image| previous_scans.dig(image["id"], "at").to_s }.first(MAX_SCANS).each do |image|
      data["scans"][image["id"]] = scan(image, containers.fetch(image["id"], []), data)
      break if data["scans"][image["id"]]["session_lost"]
    end
    data["images"].each do |image|
      data["scans"][image["id"]] ||= (previous_scans[image["id"]] || { "method" => "none" }).merge("kept" => previous_scans.key?(image["id"]))
    end
  end

  def keep?(previous, scanner)
    return false unless previous && previous["method"] == scanner && scanner && previous["at"]

    Time.zone.parse(previous["at"]) > SCAN_EVERY.ago
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
