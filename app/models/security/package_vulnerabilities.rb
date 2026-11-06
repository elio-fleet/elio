# The vulnerabilities of a server (or of the fleet) grouped by source package
# (and Docker image): what to update, to which version, how many CVEs that
# fixes, and whether the server's repositories already offer it (inventory:
# available_version of the binary packages built from that source).
#
#   PackageVulnerabilities.new(server.server_vulnerabilities, server: server).groups
class PackageVulnerabilities
  # Packages whose update only applies after a reboot (the kernel).
  REBOOT = %w[linux].freeze

  Group = Data.define(:source_package, :image, :source, :rows, :ratings, :servers, :installed_version, :target_version, :available,
                      :upgrade_packages) do
    def cves = rows.map(&:cve).uniq
    def count = cves.size
    def fixable = rows.select(&:fixable?).map(&:cve).uniq
    def fixable_count = fixable.size
    def unfixed_count = count - fixable_count

    # { "critical" => 3, … } (distinct CVEs, worst severity per CVE).
    def by_severity
      rows.group_by(&:cve).transform_values { |list| list.map(&:severity).min_by { |severity| Vulnerability::SEVERITIES.keys.index(severity) } }
          .values.tally
    end

    def severity = Vulnerability::SEVERITIES.keys.find { |key| by_severity.key?(key) } || "unknown"
    def max_score = ratings.values_at(*cves).compact.filter_map(&:score).max
    def exploited_count = ratings.values_at(*cves).compact.count(&:exploited)
    def binary_packages = rows.flat_map(&:packages).uniq.sort
    def reboot? = image.nil? && REBOOT.include?(source_package)
    def key = [ source_package, image ].compact.join("@")

    # The CVEs, fixable and most serious first.
    def ranked_rows
      rows.uniq(&:cve).sort_by do |row|
        [ row.fixable? ? 0 : 1, Vulnerability::SEVERITIES.keys.index(row.severity) || 9, -(ratings[row.cve]&.score || -1).to_f, row.cve ]
      end
    end

    # Server only: the apt command for the binary packages with an update.
    def command
      "apt-get install --only-upgrade #{upgrade_packages.join(" ")}" if upgrade_packages.any?
    end

    # :available (the repositories offer the fix), :pending (the fix exists
    # but not in the repositories yet: apt update?), :image (rebuild / pull
    # the image), :none (no fix at all).
    def state
      return :none if target_version.nil?
      return :image if image

      available ? :available : :pending
    end
  end

  # One CVE of one package (and image) on the servers it touches: what a
  # group needs, aggregated in SQL (a big fleet has tens of thousands of
  # ServerVulnerability rows, too many for Active Record objects).
  Row = Data.define(:cve, :severity, :source_package, :image, :source, :fixed_version, :installed_version, :packages, :servers) do
    def fixable? = fixed_version.present?
    def server = servers.first
  end
  # The worst severity of the aggregated rows, in the order of Vulnerability::SEVERITIES (a test checks it).
  SEVERITIES_SQL = "ARRAY['critical', 'high', 'medium', 'low', 'unknown']"
  WORST_SEVERITY = Arel.sql("(ARRAY['critical', 'high', 'medium', 'low', 'unknown'])[MIN(array_position(ARRAY['critical', 'high', 'medium', 'low', 'unknown'], server_vulnerabilities.severity::text))]")

  # `scope`: a relation of ServerVulnerability (read with a pluck) or rows already loaded.
  def initialize(scope, server: nil)
    @scope = scope
    @server = server
  end

  def groups
    @groups ||= begin
      rows = load_rows
      ratings = CveRating.for(rows.map(&:cve).uniq)
      offers = @server ? repository_offers : {}
      rows.group_by { |row| [ row.source_package, row.image, row.source ] }.map do |(package, image, source), list|
        target = list.filter_map(&:fixed_version).max { |left, right| Inventory::DebianVersion.compare(left, right) }
        installed = list.filter_map(&:installed_version).min { |left, right| Inventory::DebianVersion.compare(left, right) }
        offer = offers[package] || {}
        available = target && offer[:version] && !Inventory::DebianVersion.older?(offer[:version], target)
        Group.new(source_package: package, image: image, source: source, rows: list, ratings: ratings, servers: list.flat_map(&:servers).uniq.sort_by(&:name),
                  installed_version: installed, target_version: target, available: available.present?,
                  upgrade_packages: image ? [] : Array(offer[:packages]))
      end.sort_by { |group| sort_key(group) }
    end
  end

  # Most worth updating first: fixable ones, by worst severity, then by number.
  def sort_key(group)
    [ group.fixable_count.positive? ? 0 : 1, Vulnerability::SEVERITIES.keys.index(group.fixable_count.positive? ? fixable_severity(group) : group.severity) || 9,
      -group.fixable_count, -group.count, group.source_package, group.image.to_s ]
  end

  private

  def load_rows
    return @scope.map { |row| row_of(row) } unless @scope.is_a?(ActiveRecord::Relation)

    values = @scope.except(:includes, :preload, :order, :select).group(:cve, :source_package, :image, :source).pluck(
      :cve, :source_package, :image, :source,
      WORST_SEVERITY,
      # No DISTINCT in the aggregates (twice as slow on a big fleet): duplicates are dropped below.
      Arel.sql("ARRAY_AGG(server_vulnerabilities.fixed_version)"), Arel.sql("ARRAY_AGG(server_vulnerabilities.installed_version)"),
      Arel.sql("STRING_AGG(ARRAY_TO_STRING(server_vulnerabilities.packages, ','), ',')"), Arel.sql("ARRAY_AGG(server_vulnerabilities.server_id)")
    )
    servers = Server.where(id: values.flat_map(&:last).uniq).index_by(&:id)
    values.map do |cve, package, image, source, severity, fixed, installed, packages, server_ids|
      Row.new(cve: cve, severity: severity, source_package: package, image: image, source: source,
              fixed_version: fixed.compact.uniq.max { |left, right| Inventory::DebianVersion.compare(left, right) },
              installed_version: installed.compact.uniq.min { |left, right| Inventory::DebianVersion.compare(left, right) },
              packages: packages.to_s.split(",").uniq, servers: server_ids.uniq.filter_map { |id| servers[id] })
    end
  end

  # A ServerVulnerability already loaded (Docker page, fix commands).
  def row_of(row)
    Row.new(cve: row.cve, severity: row.severity, source_package: row.source_package, image: row.image, source: row.source,
            fixed_version: row.fixed_version, installed_version: row.installed_version, packages: row.packages, servers: [ row.server ].compact)
  end

  def fixable_severity(group)
    group.rows.select(&:fixable?).map(&:severity).min_by { |severity| Vulnerability::SEVERITIES.keys.index(severity) || 9 }
  end

  # { source package => { version: highest available, packages: binaries with an update } }
  # from the server's inventory (signed packages belong to what they sign).
  def repository_offers
    @server.packages.where(manager: "dpkg").where.not(available_version: nil).pluck(:name, :version, :source_name, :source_version, :available_version)
           .each_with_object({}) do |(name, version, source, source_version, available), offers|
      source = Vulnerabilities::Matcher.package(name, version, source: source, source_version: source_version).source
      offer = offers[source] ||= { version: nil, packages: [] }
      offer[:packages] << name
      # A signed package's version is not the one of the code it signs (grub-efi-amd64-signed 1+2.12+9+deb13u3 = grub2 2.12-9+deb13u3).
      available = Vulnerabilities::Matcher.unsigned_version(name, available)
      offer[:version] = available if offer[:version].nil? || Inventory::DebianVersion.older?(offer[:version], available)
    end
  end
end
