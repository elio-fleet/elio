# The last lines of the journal of one systemd unit (journalctl, read-only),
# read when the user opens them on the Services tab. The unit name must look
# like a systemd unit name (UNIT_NAME): it is also shell-escaped by
# Ssh::Commands, but a strict name keeps anything odd from reaching the server.
#
#   Inventory::UnitJournal.call(server, "nginx.service") # => Result(lines: [...], error: nil)
class Inventory::UnitJournal
  LINES = 50
  # Letters, digits and ":-_.\@" (systemd.unit(5)), a known unit type, never a leading "-".
  UNIT_NAME = /\A[A-Za-z0-9:_.\\@][A-Za-z0-9:_.\\@-]{0,250}\.(?:service|socket|mount|automount|swap|target|path|timer|slice|scope|device)\z/
  # A journal line longer than this is cut (a stack trace on one line, a dump).
  LINE_LENGTH = 1000

  Result = Data.define(:lines, :error) do
    def success? = error.nil?
  end

  def self.valid_name?(unit) = UNIT_NAME.match?(unit.to_s)

  def self.call(server, unit, **connection_options)
    raise ArgumentError, "invalid unit name #{unit.inspect}" unless valid_name?(unit)

    result = Ssh::Connection.open(server, **connection_options) { |ssh| ssh.run_command("inventory.unit_journal", unit: unit, lines: LINES) }
    return Result.new(lines: [], error: result.stderr.strip.presence || "exit status #{result.exit_status}") unless result.success?

    Result.new(lines: result.stdout.lines.map { |line| line.chomp.truncate(LINE_LENGTH) }.last(LINES), error: nil)
  rescue Ssh::Connection::Error => e
    Result.new(lines: [], error: e.message)
  end

  # What to run on the server to restart the unit: Elio shows it, never runs it.
  def self.restart_command(server, unit)
    "#{"sudo " unless server.username == "root"}systemctl restart #{Shellwords.escape(unit)}"
  end
end
