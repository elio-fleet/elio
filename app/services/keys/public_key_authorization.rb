# Authorizes a keyring key on a server by appending its public key to the
# authorized_keys file of an account (see AuthorizedKeysAccount): the login
# one, or another one through root (its ~/.ssh created if needed), unless the
# key is already there. The line's comment is the key name in the keyring, so it shows
# up as "known". With `expires_at`, the line gets an OpenSSH `expiry-time`
# option (OpenSSH >= 8.2) so sshd refuses the key afterwards. With `replace`,
# existing lines for the key are removed first (to change or drop an expiry).
class Keys::PublicKeyAuthorization
  Result = Data.define(:status, :error_title, :error_details) do
    def success? = status != :error
    def added? = status == :added
    def already_present? = status == :already_present
  end

  # Exit statuses of keys.append_to_account / keys.replace_in_account.
  ACCOUNT_REFUSALS = { 3 => :unknown_account, 4 => :not_owned }.freeze

  def self.call(server, public_key, account: nil, expires_at: nil, replace: false, **connection_options)
    account ||= AuthorizedKeysAccount.login(server)
    key = public_key.authorized_key
    line = line_for(public_key, expires_at)
    output = Ssh::Connection.open(server, **connection_options) do |ssh|
      if account.login?
        ssh.run_command!(replace ? "keys.replace" : "keys.append", line: line, blob: key.key).stdout
      elsif ssh.privileged?
        result = ssh.run_command(replace ? "keys.replace_in_account" : "keys.append_to_account", user: account.unix_user, line: line, blob: key.key)
        next ACCOUNT_REFUSALS.fetch(result.exit_status) if ACCOUNT_REFUSALS.key?(result.exit_status)
        raise Ssh::Connection::CommandError.new("keys.append_to_account", result) unless result.success?

        result.stdout
      else
        next :root_needed
      end
    end
    if output.is_a?(Symbol)
      return Result.new(status: :error, error_title: I18n.t("keys.public_key_authorization.#{output}_title"),
                        error_details: I18n.t("keys.public_key_authorization.#{output}_details", account: account.unix_user))
    end

    Result.new(status: output.include?("present") ? :already_present : :added, error_title: nil, error_details: nil)
  rescue Ssh::Connection::Error => e
    title, details = account.error_for(e)
    Result.new(status: :error, error_title: title, error_details: details)
  end

  def self.line_for(public_key, expires_at = nil)
    key = public_key.authorized_key
    options = %(expiry-time="#{expires_at.utc.strftime("%Y%m%d%H%M%S")}Z" ) if expires_at
    "#{options}#{key.type} #{key.key} #{public_key.name}"
  end

  # The command sent (config/ssh_commands.yml: keys.append / keys.replace),
  # also run locally by the tests.
  def self.command(line, blob, replace: false) = Ssh::Commands.render(replace ? "keys.replace" : "keys.append", line: line, blob: blob)
  def self.account_command(user, line, blob, replace: false) = Ssh::Commands.render(replace ? "keys.replace_in_account" : "keys.append_to_account", user: user, line: line, blob: blob)
end
