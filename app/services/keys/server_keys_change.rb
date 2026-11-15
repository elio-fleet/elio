# A change to a server's authorized_keys made from its keys tab, on a single
# SSH connection held under the server's key lock (Keys::WriteSession): a key
# added on one or more accounts (Keys::AccessGrant) or removed from one
# (Keys::Revocation), then every account read back on the same connection, to
# check the change is really there and to show the list without connecting
# again. Never raises: failures are in the outcomes and the read.
class Keys::ServerKeysChange
  # `outcomes`: [[AuthorizedKeysAccount, the service's Result]], in the order
  # of the accounts; `read`: a Keys::AuthorizedKeysReader::All after the change
  # (nil when nothing was sent).
  Result = Data.define(:outcomes, :read)

  def self.grant(server, public_key, accounts:, duration: nil, options: nil, **connection_options)
    blob = public_key.authorized_key.key
    missing = ->(keys) { keys.none? { |key| key.key == blob } }
    run(server, accounts, Keys::PublicKeyAuthorization::Result, :not_written, missing, connection_options) do |account, ssh|
      Keys::AccessGrant.call(server, public_key, account: account, duration: duration, options: options, ssh: ssh)
    end
  end

  # A refused key (Elio's own, not a key) is reported without connecting (`read` nil).
  def self.revoke(server, blob, account:, key_name: nil, **connection_options)
    refused = Keys::AuthorizedKeyRemoval.refusal(blob)
    return Result.new(outcomes: [ [ account, refused ] ], read: nil) if refused

    still_there = ->(keys) { keys.any? { |key| key.key == blob } }
    run(server, [ account ], Keys::AuthorizedKeyRemoval::Result, :still_there, still_there, connection_options) do |each, ssh|
      Keys::Revocation.call(server, blob, account: each, key_name: key_name, ssh: ssh)
    end
  end

  # `wrong`: true when the keys read back after a successful change show it
  # did not happen; the outcome then becomes the `mismatch` error.
  def self.run(server, accounts, result_class, mismatch, wrong, connection_options)
    outcomes, read = Keys::WriteSession.open(server, **connection_options) do |ssh|
      [ accounts.map { |account| [ account, yield(account, ssh) ] }, Keys::AuthorizedKeysReader.call_all(server, ssh: ssh) ]
    end
    checked = outcomes.map do |account, result|
      entry = read.success? && read.for(account)
      next [ account, result ] unless result.success? && entry && !entry.unreadable && wrong.call(entry.keys)

      [ account, error(result_class, I18n.t("keys.server_keys_change.#{mismatch}_title"), I18n.t("keys.server_keys_change.#{mismatch}_details", account: account.unix_user)) ]
    end
    Result.new(outcomes: checked, read: read)
  rescue Ssh::Connection::Error => e
    title, details = AuthorizedKeysAccount.login(server).error_for(e)
    Result.new(outcomes: accounts.map { |account| [ account, error(result_class, title, details) ] },
               read: Keys::AuthorizedKeysReader::All.new(accounts: [], privileged: false, error_title: title, error_details: details, reason: e.reason))
  end
  private_class_method :run

  def self.error(result_class, title, details) = result_class.new(status: :error, error_title: title, error_details: details)
  private_class_method :error
end
