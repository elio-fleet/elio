# Where Elio's key really is, server by server, from the last key scans
# (AccountSnapshot of the account Elio logs in with) and the last SSH check.
# Shown on the settings page next to the key.
class KeyPresence
  # Most worrying first; :installed is the expected state.
  STATES = %i[failing missing unreachable unknown installed].freeze
  TONES = { failing: :crit, missing: :warn, unreachable: :off, unknown: :neutral, installed: :good }.freeze
  # Server chips shown per state (the label gives the full count).
  SHOWN = 12

  def initialize(servers: Server.order(:name).to_a, app_keys: SshKey.app_keys)
    @servers = servers
    @app_keys = app_keys
  end

  def self.state_label(state, count) = I18n.t("key_presence.states.#{state}", count: count)

  # { state => [servers] } for the states that have servers, in STATES order.
  def by_state
    @by_state ||= @servers.group_by { |server| state(server) }.sort_by { |state, _| STATES.index(state) }.to_h
  end

  def count(state) = by_state.fetch(state, []).size

  def any? = @servers.any?

  # A failed SSH login comes first (the snapshot may predate it); then the
  # last key scan of Elio's own account tells whether the key is in its file.
  def state(server)
    if server.ssh_ok == false
      return server.reachable == false ? :unreachable : :failing
    end

    snapshot = snapshots[server.id]
    return :unknown unless snapshot

    snapshot.keys.any? { |key| key.matches?(@app_keys) } ? :installed : :missing
  end

  private

  # Snapshot of the login account of each server, read in one query.
  def snapshots
    @snapshots ||= AccountSnapshot.joins(:server).where("account_snapshots.unix_user = servers.username")
                                  .where(server_id: @servers.map(&:id)).index_by(&:server_id)
  end
end
