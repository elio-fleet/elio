# Checks that the app can open an SSH session on a server and run a command,
# by echoing a random token and comparing the output.
class Ssh::Check
  Result = Data.define(:success, :message, :details, :reason, :host_key) do
    def initialize(success:, message:, details:, reason: nil, host_key: nil) = super
    def success? = success
  end

  def self.call(server, **connection_options)
    token = "elio-check-#{SecureRandom.hex(4)}"
    output = Ssh::Connection.open(server, **connection_options) { |ssh| ssh.run_command!("connection.check", token: token).stdout.strip }

    if output == token
      Result.new(success: true, message: I18n.t("ssh.check.succeeded"), details: I18n.t("ssh.check.answered", username: server.username, host: server.host, token: token))
    else
      Result.new(success: false, message: I18n.t("ssh.check.unexpected"), details: I18n.t("ssh.check.unexpected_details", token: token, truncate: (output.truncate(200))))
    end
  rescue Ssh::Connection::Error => e
    if e.is_a?(Ssh::Connection::HostKeyMismatchError)
      host_key = { new: e.new_fingerprint, new_type: e.new_type, known: e.known, new_algorithm: e.new_algorithm? }
    end
    Result.new(success: false, message: e.title, details: e.message, reason: e.reason, host_key: host_key)
  end
end
