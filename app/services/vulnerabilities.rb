# Vulnerabilities (CVE) of the packages of the fleet: feeds (Debian Security
# Tracker, Ubuntu OSV) downloaded every day or imported by hand, matched with
# the packages already inventoried (no new command on the servers).
module Vulnerabilities
  class Error < StandardError; end

  # Feed of a system ({ "id" => "debian", "codename" => "bookworm" } from the
  # os inventory or a Docker image): ["debian", "bookworm"], ["ubuntu", "24.04"], or nil.
  def self.target(os_data)
    os_data ||= {}
    case os_data["id"]
    when "debian", "raspbian" then [ "debian", os_data["codename"] ].then { |target| target if target.last.present? }
    when "ubuntu" then [ "ubuntu", os_data["version_id"].to_s[/\A\d+\.\d+/] ].then { |target| target if target.last.present? }
    end
  end

  # Releases of each feed to keep: those of the servers (and of their Docker
  # images): { "debian" => ["bookworm", "trixie"], "ubuntu" => ["24.04"] }.
  def self.releases = usage.transform_values(&:keys)

  # Why each release is downloaded: the servers on it and the Docker images
  # built on it, { "debian" => { "bookworm" => { servers: 2, images: 1 } } },
  # releases in order.
  def self.usage
    usage = Vulnerability::SOURCES.keys.index_with { {} }
    count = lambda do |data, kind|
      source, release = target(data)
      (usage[source][release] ||= { servers: 0, images: 0 })[kind] += 1 if source
    end
    Inventory::Snapshot.where(category: "os").where.not(collected_at: nil).pluck(:data).each { |data| count.call(data, :servers) }
    Inventory::Snapshot.where(category: "docker").where.not(collected_at: nil).pluck(:data).each do |data|
      Array(data["images"]).each { |image| count.call(image["os"], :images) if image["os"] }
    end
    usage.transform_values { |releases| releases.sort.to_h }
  end

  # A server on a release that its feed does not hold yet — the first server
  # of a new installation, an upgrade to a new release, a Docker image on
  # another release than the servers (bookworm on a trixie fleet) — gets its
  # vulnerabilities now rather than at the next daily download. Not after a
  # failure (a closed network), nor for a release the last download could not
  # find in the feed (unavailable_releases: no download at every inventory).
  def self.cover(server)
    missing = targets_of(server).group_by(&:first).select do |source, targets|
      feed = VulnerabilityFeed.for(source)
      !feed.failed? && (targets.map(&:last) - Array(feed.releases) - Array(feed.unavailable_releases)).any?
    end
    Automation.trigger(:vulnerabilities_update) if missing.any?
  end

  # Feeds of a server: its own system and the systems of its Docker images.
  def self.targets_of(server)
    images = Array(server.inventory("docker")&.data&.dig("images")).filter_map { |image| image["os"] }
    [ server.inventory("os")&.data, *images ].filter_map { |data| target(data) }.uniq
  end

  # After an update brought new releases: the servers with Docker images that
  # waited for them are scanned again (their Docker inventory only).
  def self.rescan_images(source, releases)
    Inventory::Snapshot.where(category: "docker").where.not(collected_at: nil).includes(:server).find_each do |snapshot|
      waiting = Array(snapshot.data&.dig("scans")&.values).any? do |scan|
        scan["error"].present? && (target = target(scan["os"])) && target.first == source && releases.include?(target.last)
      end
      Inventory::CollectJob.perform_later(snapshot.server, %w[docker]) if waiting
    end
  end
end
