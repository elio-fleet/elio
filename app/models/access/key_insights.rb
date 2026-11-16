# Figures computed from the AccountSnapshots (last known keys of each server
# account): keys outside the keyring ("orphans"), per server and in total, and
# where the tolerated keys are.
class KeyInsights
  # A key outside the keyring and where it is installed: [[server, unix_user]].
  Outside = Data.define(:key, :places) do
    def fingerprint = key.fingerprint
    def servers = places.map(&:first).uniq
    def names = places.filter_map { |_, _, name| name }.uniq
    def root? = places.any? { |_, unix_user, _| unix_user == "root" }
  end

  # A tolerated key (ToleratedKey) and where it is installed now (may be none).
  Tolerated = Data.define(:record, :places)

  # Fingerprints that are not "unknown": the keyring, the keys the enabled
  # extensions know and the tolerated keys.
  def self.known_fingerprints
    PublicKey.pluck(:fingerprint).to_set + Integration.known_keys.keys + ToleratedKey.pluck(:fingerprint)
  end

  def initialize(snapshots: AccountSnapshot.includes(:server).to_a, app_key: SshKey.app_keys)
    @snapshots = snapshots
    @app_key = app_key
    @public_key_fingerprints = self.class.known_fingerprints
  end

  def scanned? = @snapshots.any?

  def orphan_count = orphans_by_server_id.values.sum(&:size)

  # { server_id => orphan keys (one per fingerprint, whatever the account) }, only for scanned servers.
  def orphans_by_server_id
    @orphans_by_server_id ||= @snapshots.group_by(&:server_id).transform_values do |snapshots|
      snapshots.flat_map { |snapshot| snapshot.unknown_keys(known_fingerprints: @public_key_fingerprints, app_key: @app_key) }
               .uniq(&:fingerprint)
    end
  end

  # Every key outside the keyring seen on the fleet, one per fingerprint, with
  # the servers and accounts where it is (most widespread first).
  def outside_keys
    @outside_keys ||= @snapshots.flat_map do |snapshot|
      snapshot.unknown_keys(known_fingerprints: @public_key_fingerprints, app_key: @app_key).map { |key| [ key, snapshot.server, snapshot.unix_user ] }
    end.group_by { |key, _, _| key.fingerprint }.map do |_, list|
      places = list.map { |key, server, unix_user| [ server, unix_user, key.name ] }.uniq.sort_by { |server, unix_user, _| [ server.name.downcase, unix_user ] }
      Outside.new(key: list.find { |key, _, _| key.named? }&.first || list.first.first, places: places)
    end.sort_by { |entry| [ -entry.places.size, entry.key.name.to_s.downcase ] }
  end

  # Every tolerated key, with the servers and accounts where it is (latest first).
  def tolerated_keys
    places = @snapshots.flat_map { |snapshot| snapshot.keys.map { |key| [ key.fingerprint, snapshot.server, snapshot.unix_user ] } }
                       .group_by(&:first)
    ToleratedKey.includes(:user).order(created_at: :desc).map do |record|
      Tolerated.new(record: record, places: places.fetch(record.fingerprint, []).map { |_, server, unix_user| [ server, unix_user ] }.uniq.sort_by { |server, unix_user| [ server.name.downcase, unix_user ] })
    end
  end

  # When each of these fingerprints was first reported as unknown (the
  # journal's unknown key activities): { fingerprint => time }.
  def self.first_seen(fingerprints)
    return {} if fingerprints.empty?

    Activity.where(kind: %w[unknown_key_detected unknown_root_key_detected]).where("data->>'fingerprint' IN (?)", fingerprints)
            .group(Arel.sql("data->>'fingerprint'")).minimum(:created_at)
  end
end
