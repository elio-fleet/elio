# Packages of a server: dpkg packages with the updates apt knows about
# (security ones flagged) and the repository they come from, snaps, and Docker
# images when Docker can be read (docker group or root). The full list goes to
# Inventory::Package (replaced at each collection); the snapshot keeps the
# counts and the last dpkg.log changes.
class Inventory::Collectors::Packages < Inventory::Collector
  def collect
    result = run("inventory.packages")
    raise Error, I18n.t("inventory.collectors.packages.failed", exit_status: (result.stderr.strip.presence || "code #{result.exit_status}")) if result.stdout.blank?

    sections = self.class.sections(result.stdout)
    return unsupported(I18n.t("inventory.collectors.packages.unsupported")) if sections["dpkg"].strip == "unsupported" && sections["snap"].strip == "unsupported"

    origins = self.class.parse_origins(sections["origins"], sections["sources"])
    packages = self.class.parse_dpkg(sections["dpkg"], self.class.parse_upgradable(sections["upgradable"]), origins) + self.class.parse_snap(sections["snap"])
    docker_error = nil
    if sections["docker"].strip == "present"
      images = run("inventory.docker_images")
      images.success? ? packages.concat(self.class.parse_docker(images.stdout)) : docker_error = docker_failure(images.stderr, I18n.t("inventory.collectors.packages.docker_unreadable", truncate: (images.stderr.strip.truncate(120))))
    end

    data = self.class.summarize(packages).merge("history" => self.class.parse_history(sections["history"]))
    docker_error ? partial(data, docker_error) : ok(data)
  end

  # Only the counts go to the snapshot; the list goes to Inventory::Package.
  def self.snapshot_data(data) = data.except("packages")

  def self.summarize(packages)
    { "packages" => packages,
      "total" => packages.size,
      "by_manager" => packages.group_by { |package| package["manager"] }.transform_values(&:size),
      "upgradable" => packages.count { |package| package["available_version"] },
      "security" => packages.count { |package| package["security"] } }
  end

  # Replaces the server's packages, and logs what changed since the previous
  # list (not on the first one).
  def self.record(server, data, _at)
    packages = Array(data["packages"])
    existing = Inventory::Package.where(server_id: server.id)
    previous = existing.pluck(:manager, :name, :arch, :version).to_h { |manager, name, arch, version| [ [ manager, name, arch ], version ] }
    current = packages.to_h { |package| [ package.values_at("manager", "name", "arch"), package["version"] ] }

    Inventory::Package.transaction do
      existing.delete_all
      rows = packages.map do |package|
        { server_id: server.id, manager: package["manager"], name: package["name"], version: package["version"], arch: package["arch"],
          source_name: package["source"] || (package["name"] if package["manager"] == "dpkg"),
          source_version: package["source_version"] || (package["version"] if package["manager"] == "dpkg"),
          available_version: package["available_version"], security: package["security"] == true, origin: package["origin"] }
      end
      Inventory::Package.insert_all(rows) if rows.any?
    end
    log_package_changes(server, previous, current) if previous.any?
    Vulnerabilities::Matcher.call(server, refresh_health: false) # Inventory::Collection refreshes the health afterwards
  end

  def self.log_package_changes(server, previous, current)
    installed = current.keys - previous.keys
    removed = previous.keys - current.keys
    upgraded = (current.keys & previous.keys).select { |key| current[key] != previous[key] }
    return if installed.empty? && removed.empty? && upgraded.empty?

    Activity.record!(:packages_changed, server: server, user: nil, installed: installed.size, upgraded: upgraded.size, removed: removed.size,
                                        examples: (upgraded + installed + removed).first(5).map { |(_, name, _)| name })
  end
  private_class_method :log_package_changes

  def self.changes(previous, data)
    return [] unless previous["security"].to_i.zero? && data["security"].to_i.positive?

    [ { kind: :security_updates_available, data: { count: data["security"] } } ]
  end

  # "ii \tlibssl3\t3.0.14-1~deb12u1\tamd64\topenssl\t3.0.14-1~deb12u1\t" (installed or on hold only).
  # The source package (what the CVE feeds list) is only kept when it differs;
  # for a signed package, the one it signs (Built-Using, see Vulnerabilities::Matcher).
  def self.parse_dpkg(text, upgradable, origins = {})
    return [] if text.strip == "unsupported"

    text.lines.filter_map do |line|
      status, name, version, arch, source, source_version, built_using = line.chomp.split("\t")
      if (signed = Vulnerabilities::Matcher.signed_source(source.presence || name.to_s, version.to_s, built_using))
        source, source_version = signed
      end
      next unless name && status.to_s.match?(/\A[ih]i/)

      update = upgradable[name]
      package = { "manager" => "dpkg", "name" => name, "version" => version, "arch" => arch,
                  "available_version" => update&.fetch("version"), "security" => update ? update["security"] : false }
      package["source"] = source if source.present? && source != name
      package["source_version"] = source_version if source_version.present? && source_version != version
      origin = origins["#{name}:#{arch}"] || origins[name]
      package["origin"] = origin if origin
      package
    end
  end

  # Repository of each installed package: { "curl" => "Debian/bookworm",
  # "libssl3:i386" => …, "elio-tool" => "local" }. `origins` (see
  # config/ssh_commands.yml): "@2\thttp://deb.debian.org/debian bookworm/main amd64 Packages"
  # numbers a source, "curl\t2,3" gives the sources of the installed version
  # (the first one is kept), "elio-tool\t" a package no repository provides.
  # `sources`: "<source>\to=Debian,a=stable,n=bookworm,…" (Release fields).
  def self.parse_origins(origins, sources)
    releases = sources.to_s.lines.filter_map { |line| line.chomp.split("\t", 2) if line.include?("\t") }.to_h
    labels = {}
    origins.to_s.lines.each_with_object({}) do |line, result|
      key, value = line.chomp.split("\t", 2)
      if key.blank?
        next
      elsif key.start_with?("@")
        labels[key.delete_prefix("@")] = origin_label(value.to_s, releases[value])
      else
        result[key] = value.to_s.split(",").filter_map { |id| labels[id] }.first || Inventory::Package::LOCAL_ORIGIN
      end
    end
  end

  # "Debian/bookworm-security": the Origin and codename (or suite) of the
  # Release file; the host and distribution of the source line without one.
  def self.origin_label(source, release)
    fields = release.to_s.split(",").filter_map { |field| field.split("=", 2) if field.include?("=") }.to_h
    url, distribution = source.split
    name = fields["o"].presence || url.to_s.sub(%r{\A\w+:/*}, "").split("/").first.presence || url
    suite = fields["n"].presence || fields["a"].presence || distribution.to_s.split("/").first
    [ name, suite ].compact_blank.join("/").truncate(100)
  end

  # Last installs, upgrades and removals of /var/log/dpkg.log, newest first:
  # "2024-09-10 14:02:11 upgrade curl:amd64 7.88.1-10+deb12u6 7.88.1-10+deb12u7"
  # (server time; "<none>" for no version).
  def self.parse_history(text)
    text.to_s.lines.filter_map do |line|
      date, time, action, package, from, to = line.split
      next unless to && %w[install upgrade remove purge].include?(action)

      { "at" => "#{date} #{time}", "action" => action, "name" => package.split(":").first,
        "from" => (from unless from == "<none>"), "to" => (to unless to == "<none>") }
    end.reverse
  end

  # "openssl/stable-security 3.0.15-1~deb12u1 amd64 [upgradable from: 3.0.14-1~deb12u1]"
  def self.parse_upgradable(text)
    text.to_s.lines.filter_map do |line|
      match = line.match(%r{\A(?<name>[^/\s]+)/(?<suites>\S+)\s+(?<version>\S+)\s+\S+\s+\[upgradable from})
      next unless match

      [ match[:name], { "version" => match[:version], "security" => match[:suites].split(",").any? { |suite| suite.end_with?("-security") } } ]
    end.to_h
  end

  # Name Version Rev Tracking Publisher Notes
  def self.parse_snap(text)
    return [] if text.strip == "unsupported"

    text.lines.drop(1).filter_map do |line|
      name, version = line.split
      { "manager" => "snap", "name" => name, "version" => version, "arch" => nil, "available_version" => nil, "security" => false } if name && version
    end
  end

  # "nginx\t1.27-alpine\t3b25b682ea82"
  def self.parse_docker(text)
    text.lines.filter_map do |line|
      repository, tag, id = line.chomp.split("\t")
      next if repository.blank? || repository == "<none>"

      { "manager" => "docker", "name" => repository, "version" => (tag == "<none>" ? id : tag), "arch" => nil, "available_version" => nil, "security" => false }
    end
  end
end
