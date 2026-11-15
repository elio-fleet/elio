# Dry run of a rotation of Elio's key on one server, read-only: can Elio log
# in (server reachable, key accepted), and could the login account add the
# new key to its authorized_keys? The rotation itself (RotateSshKeyJob) would
# fail on a server that does not pass this check.
class Keys::RotationCheck
  ANSWERS = %w[file_read_only directory_read_only home_read_only].freeze

  Result = Data.define(:status, :message) do
    def success? = status == :ready
  end

  def self.call(server, **connection_options)
    answer = Ssh::Connection.open(server, **connection_options) { |ssh| ssh.run_command!("keys.read_can_append").stdout.strip }
    return Result.new(status: :ready, message: I18n.t("keys.rotation_check.ready")) if answer == "writable"

    reason = ANSWERS.include?(answer) ? answer : "unexpected"
    Result.new(status: :read_only, message: I18n.t("keys.rotation_check.#{reason}", user: server.username))
  rescue Ssh::Connection::Error => e
    Result.new(status: e.reason == :key_refused ? :key_refused : :unreachable, message: "#{e.title} — #{e.message}")
  end
end
