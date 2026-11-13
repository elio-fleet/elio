# Last known authorized keys of a server account, as read over SSH. Keeps the
# dashboard figures and "where is this key installed?" answerable
# without connecting to every server. Refreshed on each successful read
# (key list, Keys::ServerScan) and when an expired key is removed.
class AccountSnapshot < ApplicationRecord
  belongs_to :server

  validates :unix_user, :read_at, presence: true

  # Saves the keys read on an account and logs what changed since the last
  # read: keys outside the keyring that appeared (unknown_key_detected, also on the
  # first read) and keys that vanished (key_disappeared). Keys removed through
  # Elio are forgotten beforehand, so they are not reported as vanished.
  def self.record!(server, account, keys)
    snapshot = find_or_initialize_by(server: server, unix_user: account.unix_user)
    previous = snapshot.new_record? ? nil : snapshot.keys
    snapshot.update!(content: keys.map(&:to_line).join("\n"), read_at: Time.current)
    snapshot.log_changes(previous)
    snapshot
  end

  # Records every account of a read (Keys::AuthorizedKeysReader.call_all).
  # With root, the accounts that no longer have a file (or a login shell)
  # are dropped; without, they are kept (they could not be read).
  def self.record_all!(server, read)
    read.accounts.each { |entry| record!(server, entry.account, entry.keys) unless entry.unreadable }
    where(server: server).where.not(unix_user: read.accounts.map { |entry| entry.account.unix_user }).delete_all if read.privileged
  end

  # Snapshots holding the key with this fingerprint.
  def self.with_fingerprint(fingerprint)
    includes(:server).select { |snapshot| snapshot.fingerprints.include?(fingerprint) }
  end

  def account = AuthorizedKeysAccount.new(server, unix_user)

  def login? = unix_user == server.username

  def keys
    @keys ||= AuthorizedKey.parse(content)
  end

  def fingerprints = keys.map(&:fingerprint)

  # Keys that match no public_key (named or not), except Elio's own key.
  def unknown_keys(known_fingerprints:, app_key:)
    keys.reject { |key| key.matches?(app_key) || known_fingerprints.include?(key.fingerprint) }
  end

  def log_changes(previous_keys)
    known = previous_keys.to_a.map(&:fingerprint).to_set
    orphans = unknown_keys(known_fingerprints: PublicKey.pluck(:fingerprint).to_set + Integration.known_keys.keys, app_key: SshKey.app_keys)

    orphans.reject { |key| known.include?(key.fingerprint) }.uniq(&:fingerprint).each do |key|
      Activity.record!(:unknown_key_detected, server: server, unix_user: unix_user, key_name: key.name, fingerprint: key.fingerprint)
    end
    return unless previous_keys

    current = fingerprints.to_set
    previous_keys.reject { |key| current.include?(key.fingerprint) }.uniq(&:fingerprint).each do |key|
      Activity.record!(:key_disappeared, server: server, unix_user: unix_user, key_name: key.name, fingerprint: key.fingerprint)
    end
  end

  # Drops a key removed from the server (e.g. an expired temporary access).
  def forget!(blob)
    update!(content: keys.reject { |key| key.key == blob }.map(&:to_line).join("\n"))
  end

  def content=(value)
    @keys = nil
    super
  end
end
