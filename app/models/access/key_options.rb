# Restrictions an operator puts on a key when adding it to a server (OpenSSH
# authorized_keys options, see sshd(8)): the addresses it may log in from
# (`from=`, the format of KeyInstallGuide), a forced command (`command=`) and
# no port forwarding. Checked strictly, then written quoted with their double
# quotes escaped, so a value can never end its option early or add another one.
class KeyOptions
  # Printable ASCII only: no tab, newline or other control character.
  COMMAND_FORMAT = /\A[\x20-\x7E]+\z/
  MAX_COMMAND_LENGTH = 300
  MAX_FROM_LENGTH = 200

  attr_reader :from, :command, :no_port_forwarding, :errors

  # From the "Add a key" form: { "from" => …, "command" => …, "no_port_forwarding" => "1" }.
  def self.from_params(params)
    params = params.to_h.with_indifferent_access
    new(from: params[:from], command: params[:command], no_port_forwarding: params[:no_port_forwarding] == "1")
  end

  def initialize(from: nil, command: nil, no_port_forwarding: false)
    @errors = []
    @from = restriction(from.to_s.gsub(/\s+/, ""))
    @command = forced_command(command.to_s.strip)
    @no_port_forwarding = no_port_forwarding == true
  end

  def valid? = errors.empty?

  def empty? = to_a.empty?

  # ["from=\"10.0.0.0/8\"", "command=\"…\"", "no-port-forwarding"]: in front of
  # the key, comma separated.
  def to_a
    [
      (%(from="#{from}") if from),
      (%(command="#{command.gsub('"', '\\"')}") if command),
      ("no-port-forwarding" if no_port_forwarding)
    ].compact
  end

  def to_s = to_a.join(",")

  # One sentence per error, for the flash.
  def error_messages = errors.map { |field| I18n.t("key_options.errors.#{field}") }

  private

  def restriction(value)
    return if value.empty?
    return value if value.length <= MAX_FROM_LENGTH && value.match?(KeyInstallGuide::FROM_FORMAT)

    @errors << :from
    nil
  end

  # sshd reads `\"` as a quote inside the value: a command ending with a
  # backslash would swallow the closing quote, and break the line.
  def forced_command(value)
    return if value.empty?
    return value if value.length <= MAX_COMMAND_LENGTH && value.match?(COMMAND_FORMAT) && !value.end_with?("\\")

    @errors << :command
    nil
  end
end
