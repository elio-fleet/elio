# Removes a public key from the authorized_keys file of an account (see
# AuthorizedKeysAccount): the login account, or another one through root. The protected keys (Elio's, by default) are refused:
# every line whose key blob is `blob` is dropped, other lines (comments,
# other keys) are kept byte for byte. The Elio key can never be removed,
# since the app would lose access to the server.
class Keys::AuthorizedKeyRemoval
  BLOB_FORMAT = %r{\A[A-Za-z0-9+/]+={0,2}\z}

  Result = Data.define(:status, :error_title, :error_details) do
    def success? = %i[removed absent].include?(status)
    def removed? = status == :removed
    def absent? = status == :absent
  end

  def self.call(server, blob, account: nil, protected_keys: SshKey.app_keys, **connection_options)
    account ||= AuthorizedKeysAccount.login(server)
    return error(I18n.t("keys.authorized_key_removal.invalid_title"), I18n.t("keys.authorized_key_removal.invalid_details")) unless blob.to_s.match?(BLOB_FORMAT)
    return error(I18n.t("keys.authorized_key_removal.forbidden_title"), I18n.t("keys.authorized_key_removal.forbidden_details")) if Array(protected_keys).any? { |key| key.blob == blob }

    output = Ssh::Connection.open(server, **connection_options) do |ssh|
      if account.login?
        ssh.run_command!("keys.remove", blob: blob).stdout
      elsif ssh.privileged?
        ssh.run_command!("keys.remove_from_account", user: account.unix_user, blob: blob).stdout
      else
        next :root_needed
      end
    end
    return error(I18n.t("keys.authorized_key_removal.root_needed_title"), I18n.t("keys.authorized_key_removal.root_needed_details", account: account.unix_user)) if output == :root_needed

    Result.new(status: output.include?("removed") ? :removed : :absent, error_title: nil, error_details: nil)
  rescue Ssh::Connection::Error => e
    error(*account.error_for(e))
  end

  # The command sent (config/ssh_commands.yml: keys.remove), also run locally by the tests.
  def self.command(blob) = Ssh::Commands.render("keys.remove", blob: blob)

  def self.error(title, details)
    Result.new(status: :error, error_title: title, error_details: details)
  end
  private_class_method :error
end
