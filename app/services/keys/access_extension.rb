# Extends an active TemporaryAccess by `duration` from its current end: the
# `expiry-time` option of its authorized_keys line is changed in place (the
# other options, such as from= or command=, and the comment stay as they are),
# then the access gets its new end. Its scheduled ExpireTemporaryAccessJob
# reschedules itself when it runs before the new end. Runs under the server's
# key lock (Keys::WriteSession), the access read again once it is held.
#
# An access already past its end cannot be extended: sshd refuses the key and
# the expiry job is removing it.
class Keys::AccessExtension
  Result = Data.define(:status, :error_title, :error_details) do
    def success? = status == :extended
  end

  def self.call(access, duration, **connection_options)
    return error(:expired) if !access.active? || access.expired?

    output = run(access, duration, **connection_options)
    return error(output, account: access.unix_user) unless output == :extended

    Activity.record!(:key_access_extended, server: access.server, public_key: access.public_key, unix_user: access.unix_user,
                                           key_name: access.public_key&.name, fingerprint: access.fingerprint,
                                           duration_seconds: duration.to_i, expires_at: access.expires_at.iso8601)
    Result.new(status: :extended, error_title: nil, error_details: nil)
  rescue Ssh::Connection::Error => e
    title, details = access.account.error_for(e)
    Result.new(status: :error, error_title: title, error_details: details)
  end

  # :extended (the access updated), :expired (ended meanwhile), :absent (no
  # expiring line for the key any more) or an account refusal.
  def self.run(access, duration, **connection_options)
    account = access.account
    Keys::WriteSession.open(access.server, **connection_options) do |ssh|
      next :expired if !access.reload.active? || access.expired?

      expires_at = access.expires_at + duration
      output = write(ssh, access, account, expires_at.utc.strftime("%Y%m%d%H%M%SZ"))
      access.update!(expires_at: expires_at, extensions_count: access.extensions_count + 1, expiry_reminded_at: nil) if output == :extended
      output
    end
  end
  private_class_method :run

  def self.write(ssh, access, account, expiry)
    if account.login?
      ssh.run_command!("keys.extend", blob: access.key_blob, expiry: expiry).stdout.include?("extended") ? :extended : :absent
    elsif ssh.privileged?
      result = ssh.run_command("keys.extend_in_account", user: account.unix_user, blob: access.key_blob, expiry: expiry)
      return Keys::PublicKeyAuthorization::ACCOUNT_REFUSALS.fetch(result.exit_status) if Keys::PublicKeyAuthorization::ACCOUNT_REFUSALS.key?(result.exit_status)
      raise Ssh::Connection::CommandError.new("keys.extend_in_account", result) unless result.success?

      result.stdout.include?("extended") ? :extended : :absent
    else
      :root_needed
    end
  end
  private_class_method :write

  def self.error(reason, account: nil)
    scope = reason.in?(%i[expired absent]) ? "keys.access_extension" : "keys.public_key_authorization"
    Result.new(status: :error, error_title: I18n.t("#{scope}.#{reason}_title"), error_details: I18n.t("#{scope}.#{reason}_details", account: account))
  end
  private_class_method :error

  # The command sent (config/ssh_commands.yml: keys.extend), also run locally by the tests.
  def self.command(blob, expiry) = Ssh::Commands.render("keys.extend", blob: blob, expiry: expiry)
end
