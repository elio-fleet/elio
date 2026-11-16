# Adds several keyring keys to several servers (on the login user of each, or
# on the account named `unix_user` through root), or removes a keyring key from
# every account where it is known to be installed (someone leaves),
# a few servers at a time (BoundedParallel), the keys (or accounts) of one
# server one after the other. Used by the keyring key page.
# Never raises: each (server, public_key, account) outcome is returned as a
# Result, in the servers' order.
class Keys::BulkAccess
  Result = Data.define(:server, :public_key, :unix_user, :status, :message) do
    def error? = status == :error
  end

  def self.grant(public_keys, servers, duration: nil, unix_user: nil)
    BoundedParallel.map(servers) { |server| grant_on(server, public_keys, duration, unix_user) }.flatten
  end

  # Removes `public_key` from every account of Keys::PublicKeyAccessOverview
  # (the last key reads), through Keys::Revocation (temporary accesses ended,
  # snapshot updated, activity logged).
  def self.revoke(public_key)
    accesses = Keys::PublicKeyAccessOverview.new(public_key).accesses.group_by(&:server)
    BoundedParallel.map(accesses) { |server, server_accesses| revoke_on(server, server_accesses, public_key) }.flatten
  end

  def self.revoke_on(server, accesses, public_key)
    accesses.filter_map do |access|
      account = AuthorizedKeysAccount.for(server, access.unix_user) or next
      outcome = Keys::Revocation.call(server, public_key.authorized_key.key, account: account, key_name: public_key.authorized_key.comment || public_key.name, public_key: public_key)
      message = if outcome.removed? then I18n.t("keys.bulk_access.removed")
      elsif outcome.absent? then I18n.t("keys.bulk_access.absent")
      else "#{outcome.error_title} — #{outcome.error_details}"
      end
      Result.new(server, public_key, account.unix_user, outcome.status, message)
    end
  end
  private_class_method :revoke_on

  def self.grant_on(server, public_keys, duration, unix_user)
    account = AuthorizedKeysAccount.for(server, unix_user) || AuthorizedKeysAccount.login(server)
    results = public_keys.map do |public_key|
      outcome = Keys::AccessGrant.call(server, public_key, account: account, duration: duration)
      message = if outcome.added? then duration ? I18n.t("keys.bulk_access.added_for", label_for: (TemporaryAccess.label_for(duration))) : I18n.t("keys.bulk_access.added")
      elsif outcome.already_present? then I18n.t("keys.bulk_access.present")
      else "#{outcome.error_title} — #{outcome.error_details}"
      end
      Result.new(server, public_key, account.unix_user, outcome.status, message)
    end
    refresh_snapshot(server, account) unless results.all?(&:error?)
    results
  end
  private_class_method :grant_on

  def self.refresh_snapshot(server, account)
    return Keys::ServerScan.call(server) unless account.login?

    read = Keys::AuthorizedKeysReader.call(server, account: account)
    AccountSnapshot.record!(server, account, read.keys) if read.success?
  end
  private_class_method :refresh_snapshot
end
