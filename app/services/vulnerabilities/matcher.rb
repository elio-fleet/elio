# Finds the CVEs affecting a server from its dpkg packages (by source package
# and source version) and the feed of its release: a CVE without a fix yet, or
# fixed in a version newer than the installed one. Replaces the server's
# ServerVulnerability rows of that origin; logs vulnerability_found for the
# fixable ones at the alert severity (AppSetting) that are new since the
# previous match (never on the first one).
module Vulnerabilities::Matcher
  Package = Data.define(:name, :source, :version)

  # Signed packages (Secure Boot) are built from a source package of their
  # own, whose version is not the one of the signed code: grub-efi-amd64-signed
  # 1+2.12+9+deb13u2 signs grub2 2.12-9+deb13u2, shim-signed
  # 1.51~1+deb13u1+16.1-2~deb13u1 signs shim 16.1-2~deb13u1, fwupd-amd64-signed
  # 1:1.7+1 signs fwupd-efi 1:1.7-1, linux-image-* (from linux-signed-amd64
  # 6.12.107+1) are linux 6.12.107-1. The feeds list the CVEs under the signed
  # code: compared as such, "1+2.12…" looked older than grub2's fix 2.12-6.
  #
  # dpkg's Built-Using field names it ("grub2 (= 2.12-9+deb13u2)"); without
  # it (an older inventory, a version offered by apt) the version is deduced
  # from the signed one.
  SIGNED_SOURCES = [
    [ /\Alinux-signed(-.+)?\z/, "linux", ->(version) { version } ], # the binary version is linux's
    [ /\Agrub-efi-.+-signed\z/, "grub2", ->(version) { version.sub(/\A\d+\+/, "").sub("+", "-") } ],
    [ /\Ashim-signed\z/, "shim", ->(version) { version[/\+([^+]*-[^+]*)\z/, 1] || version } ],
    [ /\Afwupd-.+-signed\z/, "fwupd-efi", ->(version) { version.sub(/\+(\d+)\z/, '-\\1') } ]
  ].freeze

  # A dpkg package for the feeds: its source package and source version
  # (the binary ones when absent; the signed code for a signed package).
  def self.package(name, version, source: nil, source_version: nil, built_using: nil)
    source ||= name
    if (signed = signed_source(source, version, built_using))
      return Package.new(name, *signed)
    end

    Package.new(name, source, source_version || version)
  end

  # [source, version] of the code a signed package signs, nil for any other.
  def self.signed_source(source, version, built_using = nil)
    return unless source.end_with?("-signed") || SIGNED_SOURCES.any? { |pattern, _, _| pattern.match?(source) }

    _, unsigned, deduce = SIGNED_SOURCES.find { |pattern, _, _| pattern.match?(source) }
    built = parse_built_using(built_using)
    match = built.find { |name, _| name == unsigned } || (built.first if built.one?)
    return match if match
    return [ unsigned, deduce.call(version) ] if unsigned

    nil
  end

  # The version of the signed code for a version of a signed binary package
  # (an update offered by apt: no Built-Using for it).
  def self.unsigned_version(name, version)
    _, _, deduce = SIGNED_SOURCES.find { |pattern, _, _| pattern.match?(name) }
    deduce ? deduce.call(version) : version
  end

  # "grub2 (= 2.12-9+deb13u2), lzo2 (= 2.10-3)" → [["grub2", "2.12-9+deb13u2"], ["lzo2", "2.10-3"]]
  def self.parse_built_using(text)
    text.to_s.split(",").filter_map { |entry| entry.strip.match(/\A(\S+)\s*\(=\s*([^)\s]+)\s*\)\z/)&.captures }
  end

  def self.call_all
    Server.includes(:inventory_snapshots).find_each { |server| call(server) }
  end

  def self.call(server, refresh_health: true)
    # Read from the database: during a collection, a copy loaded before it would hold the previous kernel.
    os = Inventory::Snapshot.find_by(server_id: server.id, category: "os")&.data || {}
    target = Vulnerabilities.target(os)
    return unless target && VulnerabilityFeed.for(target.first).releases.include?(target.last)

    packages = server.packages.where(manager: "dpkg").pluck(:name, :source_name, :source_version, :version)
                     .map { |name, source, source_version, version| package(name, version, source: source, source_version: source_version) }
    rows = affected(*target, packages, running_kernel: os["kernel"]).map { |row| row.merge(server_id: server.id, origin: "host", image: nil) }
    replace(server, rows, origin: "host", log: server.vulnerabilities_checked_at.present?)
    server.update_columns(vulnerabilities_checked_at: Time.current)
    server.refresh_health! if refresh_health
  end

  # CVEs of `packages` (Package) in a feed release: rows without server_id.
  # The oldest installed version of a source counts, except for the kernel:
  # the running one (an old kernel left installed does not run).
  def self.affected(source, release, packages, running_kernel: nil)
    by_source = packages.group_by(&:source)
    if running_kernel && (running = by_source["linux"]&.find { |package| package.name == "linux-image-#{running_kernel}" })
      by_source["linux"] = [ running ] + by_source["linux"].reject { |package| package.name.start_with?("linux-image-") }
    end
    return [] if by_source.empty?

    Vulnerability.where(source: source, release: release, package: by_source.keys)
                 .pluck(:package, :cve, :fixed_version, :severity, :description).filter_map do |package, cve, fixed, severity, description|
      installed = by_source.fetch(package).map(&:version).compact.min { |left, right| Inventory::DebianVersion.compare(left, right) }
      next if fixed && installed && !Inventory::DebianVersion.older?(installed, fixed)

      { source: source, cve: cve, source_package: package, packages: by_source.fetch(package).map(&:name).uniq.sort,
        installed_version: installed, fixed_version: fixed, severity: severity, description: description }
    end
  end

  # Replaces the rows of an origin (and image), logging the new serious ones
  # when `log` (not on a first match).
  def self.replace(server, rows, origin:, image: :all, log: true)
    scope = server.server_vulnerabilities.where(origin: origin)
    scope = scope.where(image: image) unless image == :all
    known = scope.pluck(:cve).to_set
    rows = with_severity(rows)
    ServerVulnerability.transaction do
      scope.delete_all
      ServerVulnerability.insert_all(rows) if rows.any?
    end
    log_new(server, rows, known) if log
  end

  # The severity of the feed (or scanner) is kept as `distro_severity`; when
  # it did not rate the CVE, the one of its score (CveRating) is used.
  def self.with_severity(rows)
    unrated = rows.select { |row| row[:severity] == "unknown" }.map { |row| row[:cve] }
    ratings = unrated.any? ? CveRating.where(cve: unrated).pluck(:cve, :score).to_h : {}
    rows.map do |row|
      severity = row[:severity] == "unknown" ? CveRating.severity_for(ratings[row[:cve]]) : row[:severity]
      row.merge(distro_severity: row[:severity], severity: severity)
    end
  end

  # Logs vulnerability_found for these CVEs of a server (the fixable ones at
  # the alert severity that were not there before).
  def self.log_serious(server, cves, origin: nil, image: nil)
    return if cves.empty?

    rows = server.server_vulnerabilities.where(cve: cves.to_a)
    rows = rows.where(origin: origin) if origin
    rows = rows.where(image: image) if image
    # One activity for the server's own packages, one per image: they are not
    # fixed the same way.
    rows.group_by(&:image).sort_by { |key, _| key.to_s }.each do |row_image, list|
      ordered = list.sort_by { |row| -Vulnerability.severity_rank(row.severity) }
      Activity.record!(:vulnerability_found, server: server, user: nil, count: ordered.map(&:cve).uniq.size, cves: ordered.map(&:cve).uniq.first(5),
                                             packages: ordered.map(&:source_package).uniq.first(5), image: row_image)
    end
  end

  def self.log_new(server, rows, known)
    minimum = AppSetting.current.vulnerability_alert_severity
    return if minimum == "none"

    serious = rows.select { |row| row[:fixed_version] && row[:severity].in?(Vulnerability.severities_from(minimum)) && !known.include?(row[:cve]) }
    return if serious.empty?

    log_serious(server, serious.map { |row| row[:cve] }.to_set, origin: serious.first[:origin], image: serious.first[:image])
  end
  private_class_method :log_new
end
