# Replaces the entries of a feed (download, or a file imported by hand) with
# those of the releases used on the fleet, then matches every server again.
#
#   Vulnerabilities::Update.call("debian")                    # download
#   Vulnerabilities::Update.call("debian", path: "…", origin: "import")
#
# Returns a French summary; raises Vulnerabilities::Error (remembered on the feed).
module Vulnerabilities::Update
  READERS = { "debian" => Vulnerabilities::DebianTracker, "ubuntu" => Vulnerabilities::UbuntuOsv }.freeze
  BATCH = 5_000

  # One update of a feed at a time (a download and an import by hand): the
  # second waits for the first, then replaces its entries.
  def self.call(source, path: nil, origin: path ? "import" : "download")
    AdvisoryLock.hold("vulnerability_feed:#{source}") { update(source.to_s, path, origin) }
  end

  def self.update(source, path, origin)
    reader = READERS.fetch(source)
    releases = Vulnerabilities.releases.fetch(source)
    feed = VulnerabilityFeed.for(source)
    return I18n.t("vulnerabilities.update.no_server", label: feed.label) if releases.empty?

    fingerprints = nil
    remember = -> { fingerprints ||= fingerprints(source) } # before the first change, never for files left as they were
    validators = {}
    if path
      covered = reader.respond_to?(:archive_releases) ? reader.archive_releases(path) : nil
      remember.call
      import(reader, source, path, covered ? releases & covered : releases)
    else
      validators = download(reader, source, feed, releases, remember)
    end
    remember.call if Vulnerability.where(source: source).where.not(release: releases).exists?
    Vulnerability.where(source: source).where.not(release: releases).delete_all
    count = Vulnerability.where(source: source).count
    before = Array(feed.releases)
    held = Vulnerability.where(source: source).distinct.order(:release).pluck(:release)
    feed.update!(refreshed_at: Time.current, origin: origin, entries_count: count, releases: held, unavailable_releases: releases - held,
                 download_validators: validators)
    Vulnerabilities::Matcher.call_all(changes(source, fingerprints, held - before))
    Vulnerabilities.rescan_images(source, held - before) if (held - before).any?
    I18n.t("vulnerabilities.update.done", label: feed.label, count: count, releases_join: (feed.releases.join(", ")))
  rescue Vulnerabilities::Error => e
    feed&.update!(failed_at: Time.current, last_error: e.message)
    raise
  end

  # One download per file (Debian: one for every release, Ubuntu: one per
  # release), conditional when the feed already holds all its releases from
  # a download (not after an import by hand: its file may be older): a file
  # that has not changed keeps its entries. Returns the validators to keep.
  def self.download(reader, source, feed, releases, remember)
    known = Array(feed.releases) + Array(feed.unavailable_releases)
    releases.group_by { |release| reader.url(release) }.to_h do |url, url_releases|
      previous = feed.origin == "download" && (url_releases - known).empty? ? feed.download_validators[url] : nil
      received = Vulnerabilities::Download.open(url, validators: previous) do |file, answer|
        remember.call
        import(reader, source, file, url_releases)
        answer
      end
      [ url, received == :not_modified ? previous : received ]
    end.compact_blank
  end

  # A digest of the entries of each package of each release:
  # { ["bookworm", "openssl"] => "9e1…" }.
  def self.fingerprints(source)
    digest = Arel.sql("md5(string_agg(concat_ws('|', cve, fixed_version, severity, distro_status, md5(coalesce(description, ''))), ',' ORDER BY cve))")
    Vulnerability.where(source: source).group(:release, :package).pluck(:release, :package, digest).to_h { |release, package, sum| [ [ release, package ], sum ] }
  end

  # What the servers must match again: { ["debian", "bookworm"] => ["openssl"] }
  # for the packages whose entries changed, :all for a release new to the
  # feed; nothing when no file changed.
  def self.changes(source, before, new_releases)
    return {} unless before

    after = fingerprints(source)
    changed = (before.keys | after.keys).reject { |key| before[key] == after[key] }
    by_release = changed.group_by(&:first).transform_values { |keys| keys.map(&:last) }
    new_releases.each { |release| by_release[release] = :all }
    by_release.transform_keys { |release| [ source, release ] }
  end

  # Replaces the entries of each release found in the file (a release absent
  # from it keeps its entries: an Ubuntu archive holds one release).
  def self.import(reader, source, path, releases)
    Vulnerability.transaction do
      replaced = Set.new
      batch = {}
      flush = lambda do
        primary, secondary = batch.values.partition { |row| row.delete(:primary) }
        Vulnerability.upsert_all(primary, unique_by: :index_vulnerabilities_uniqueness) if primary.any?
        Vulnerability.insert_all(secondary, unique_by: :index_vulnerabilities_uniqueness) if secondary.any? # never replaces a primary row
        batch = {}
      end
      each_row(reader, path, releases) do |row|
        Vulnerability.where(source: source, release: row[:release]).delete_all if replaced.add?(row[:release])
        key = row.values_at(:release, :package, :cve)
        next if batch[key]&.dig(:primary) && !row[:primary]

        batch[key] = row.merge(source: source)
        flush.call if batch.size >= BATCH
      end
      flush.call
      raise Vulnerabilities::Error, I18n.t("vulnerabilities.update.nothing_for_fleet", releases_join: (releases.join(", "))) if replaced.empty?
    end
  end

  def self.each_row(reader, path, releases, &block)
    if reader == Vulnerabilities::DebianTracker
      File.open(path, "rb") { |io| reader.each_row(io, releases: releases, &block) }
    else
      reader.each_row(path, releases: releases, &block)
    end
  end
  private_class_method :download, :fingerprints, :changes, :import, :each_row

  # Kind of a file imported by hand: a zip (Ubuntu OSV) or JSON (Debian).
  def self.detect(path)
    head = File.binread(path, 4).to_s
    if head.start_with?("PK") then "ubuntu"
    elsif head.lstrip.start_with?("{") then "debian"
    end
  end
end
