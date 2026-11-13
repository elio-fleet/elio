# Adds several keyring keys to several servers (on the login user of each, or
# on the account named `unix_user` through root),
# a few servers at a time (BoundedParallel), the keys of one server one after
# the other. Used by the keyring key page.
# Never raises: each (server, public_key) outcome is returned as a Result, in
# the servers' order.
class Keys::BulkAccess
  Result = Data.define(:server, :public_key, :unix_user, :status, :message) do
    def error? = status == :error
  end

  def self.grant(public_keys, servers, duration: nil, unix_user: nil)
    BoundedParallel.map(servers) { |server| grant_on(server, public_keys, duration, unix_user) }.flatten
  end

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
