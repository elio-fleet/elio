# Figures computed from the AccountSnapshots (last known keys of each server
# account): keys outside the keyring ("orphans"), per server and in total.
class KeyInsights
  # A key outside the keyring and where it is installed: [[server, unix_user]].
  Outside = Data.define(:key, :places) do
    def fingerprint = key.fingerprint
    def servers = places.map(&:first).uniq
    def names = places.filter_map { |_, _, name| name }.uniq
  end

  def initialize(snapshots: AccountSnapshot.includes(:server).to_a, app_key: SshKey.app_keys)
    @snapshots = snapshots
    @app_key = app_key
    @public_key_fingerprints = PublicKey.pluck(:fingerprint).to_set + Integration.known_keys.keys
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
end
