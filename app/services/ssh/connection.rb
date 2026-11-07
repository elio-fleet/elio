require "net/ssh"

# Opens an SSH session to a Server to run commands (no interactive shell).
# The commands come from config/ssh_commands.yml (see Ssh::Commands):
#
#   Ssh::Connection.open(server) do |ssh|
#     ssh.run_command!("keys.read").stdout
#   end
#
# Authentication only uses the app's SSH keys (SshKey.app_keys: the active key,
# plus the pending one during a rotation), never ~/.ssh nor the ssh-agent.
# Host keys are trusted on first use and pinned in KNOWN_HOSTS_FILE; a changed
# key aborts the connection.
class Ssh::Connection
  # Each error has a short French `title` to show in the UI next to its message.
  # `reason` lets the UI guide the user: :key_refused (install the app key on
  # the server) or :missing_key (generate it in the settings).
  class Error < StandardError
    def title = I18n.t("ssh.connection.error")
    def reason = nil
  end

  class ConnectionError < Error
    def title = I18n.t("ssh.connection.connection")
  end

  class AuthenticationError < Error
    def title = I18n.t("ssh.connection.authentication")
    def reason = :key_refused
  end

  # Carries the fingerprint the server presents and the pinned ones, so an
  # admin can decide to trust the new one (ServerHostKeysController).
  class HostKeyMismatchError < Error
    attr_reader :new_fingerprint, :known_fingerprints

    def initialize(message = nil, new_fingerprint: nil, known_fingerprints: [])
      @new_fingerprint = new_fingerprint
      @known_fingerprints = known_fingerprints
      super(message)
    end

    def title = I18n.t("ssh.connection.host_key_mismatch")
    def reason = :host_key_changed
  end

  class MissingKeyError < Error
    def title = I18n.t("ssh.connection.missing_key")
    def reason = :missing_key
  end

  # The command ran longer than its time limit: its channel and the session
  # are closed, so the connection cannot be used anymore.
  class CommandTimeoutError < Error
    def title = I18n.t("ssh.connection.timeout")
  end

  class CommandError < Error
    attr_reader :result

    def title = I18n.t("ssh.connection.command")

    def initialize(command, result)
      @result = result
      super("`#{command}` exited with status #{result.exit_status}: #{result.stderr.strip.presence || "no output"}")
    end
  end

  Result = Data.define(:stdout, :stderr, :exit_status) do
    def success? = exit_status.zero?
  end

  KNOWN_HOSTS_FILE = Rails.root.join("storage", "ssh", "known_hosts")
  DEFAULT_TIMEOUT = 10 # seconds, to connect
  DEFAULT_COMMAND_TIMEOUT = 60 # seconds, per command

  attr_reader :server

  def self.open(server, **options, &block)
    new(server, **options).open(&block)
  end

  # `transport` is the Net::SSH-compatible entry point, swappable in tests.
  # `key`: one SshKey or a list, tried in order (the app keys by default).
  # `command_timeout`: delay of the commands run with #exec, and a ceiling
  # for those of config/ssh_commands.yml (their own `timeout`) when given.
  def initialize(server, key: SshKey.app_keys, timeout: DEFAULT_TIMEOUT, command_timeout: nil,
                 known_hosts_file: Ssh::KnownHosts.file, transport: Net::SSH)
    @server = server
    @keys = Array(key).compact
    @timeout = timeout
    @command_timeout = command_timeout
    @known_hosts_file = Pathname(known_hosts_file)
    @transport = transport
  end

  # Yields the connection and closes the session afterwards. Returns the block's value.
  def open
    raise MissingKeyError, I18n.t("ssh.connection.missing_key_details") if @keys.empty?

    FileUtils.mkdir_p(@known_hosts_file.dirname)

    @transport.start(server.host, server.username, **ssh_options) do |session|
      @session = session
      yield self
    ensure
      @session = nil
      @privilege = nil
      @distros = nil
      @timed_out = false
    end
  rescue Net::SSH::AuthenticationFailed => e
    raise AuthenticationError, I18n.t("ssh.connection.authentication_details", username: server.username, host: server.host, message: e.message)
  rescue Net::SSH::HostKeyMismatch => e
    raise HostKeyMismatchError.new(I18n.t("ssh.connection.host_key_details", host: server.host, fingerprint: e.fingerprint),
                                   new_fingerprint: e.fingerprint,
                                   known_fingerprints: Ssh::KnownHosts.fingerprints(server.host, server.port, file: @known_hosts_file))
  rescue Net::SSH::ConnectionTimeout, Net::SSH::Disconnect, Net::SSH::Exception, SocketError, SystemCallError, IOError, Timeout::Error => e
    raise ConnectionError, I18n.t("ssh.connection.connection_details", host: server.host, port: server.port, class: e.class, message: e.message)
  end

  # Runs a command and returns its Result, whatever the exit status. Raises
  # CommandTimeoutError (and shuts the session down) after `timeout` seconds.
  def exec(command, timeout: @command_timeout || DEFAULT_COMMAND_TIMEOUT)
    raise CommandTimeoutError, I18n.t("ssh.connection.session_closed") if @timed_out
    raise Error, "No open session, call #exec inside Ssh::Connection.open" unless @session

    # net-ssh hands over bytes (BINARY), cut anywhere, even inside a
    # character: collect them, then read the whole as UTF-8 (see #text).
    stdout = String.new(encoding: Encoding::BINARY)
    stderr = String.new(encoding: Encoding::BINARY)
    exit_status = -1
    channel = @session.open_channel do |opened|
      opened.exec(command) do |_channel, started|
        next stderr << "the server refused to run the command" unless started

        opened.on_data { |_, data| stdout << data }
        opened.on_extended_data { |_, _, data| stderr << data }
        opened.on_request("exit-status") { |_, data| exit_status = data.read_long }
      end
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    @session.loop(0.1) { channel.active? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline }
    raise_timeout(command, timeout) if channel.active?

    Result.new(stdout: text(stdout), stderr: text(stderr), exit_status: exit_status)
  end

  # Runs a command and raises CommandError unless it succeeds.
  def exec!(command, **options)
    exec(command, **options).tap { |result| raise CommandError.new(command, result) unless result.success? }
  end

  # Runs a command of config/ssh_commands.yml (key "role.name"): the variant
  # of the server's distribution family, through sudo when it needs root
  # (as is without root access: it runs with the user's rights), values
  # shell-escaped. Returns its Result whatever the exit status.
  def run_command(key, timeout: nil, **values)
    command = Ssh::Commands.fetch(key)
    line = command.render(distros: (command.distro_specific? ? distros : []), **values)
    line = privileged(line) if command.root?
    exec(line, timeout: timeout || [ command.timeout, @command_timeout ].compact.min)
  end

  # Same, raising CommandError unless it succeeds.
  def run_command!(key, **options)
    run_command(key, **options).tap { |result| raise CommandError.new(key, result) unless result.success? }
  end

  # Distribution family of the server (ID then ID_LIKE of /etc/os-release, e.g.
  # ["ubuntu", "debian"]), read once per session when a command has variants;
  # [] when unknown (the default variants are used).
  def distros
    @distros ||= Ssh::Commands.parse_distros(run_command("connection.os_release").then { |result| result.success? ? result.stdout : "" })
  end

  # How commands needing root can run on this server, checked once per session:
  # :root (logged in as root), :sudo (passwordless `sudo -n`) or :none.
  def privilege
    @privilege ||= if server.username == "root" then :root
    elsif run_command("connection.sudo_probe").success? then :sudo
    else :none
    end
  end

  def privileged? = privilege != :none

  # `command` prefixed with `sudo -n` when root is reached through sudo; as is
  # otherwise (already root, or no root access: it runs with the user's rights).
  def privileged(command) = privilege == :sudo ? "sudo -n #{command}" : command

  private

  # Outputs are UTF-8 text from here on: a BINARY string with accents cannot
  # be written as JSON (json 3.1 raises) nor compared with UTF-8 text; bytes
  # that are not UTF-8 become "\uFFFD".
  def text(bytes) = bytes.force_encoding(Encoding::UTF_8).scrub

  def raise_timeout(command, timeout)
    @session.shutdown!
    @timed_out = true
    raise CommandTimeoutError, I18n.t("ssh.connection.command_timeout", timeout: timeout, host: server.host, truncate: (command.truncate(80)))
  end

  def ssh_options
    {
      port: server.port,
      timeout: @timeout,
      non_interactive: true,          # never prompt on the app's stdin
      config: false,                  # ignore the app user's ~/.ssh/config
      verify_host_key: :accept_new,   # trust on first use, reject changed keys
      user_known_hosts_file: @known_hosts_file.to_s,
      global_known_hosts_file: [],
      keepalive: true,
      keepalive_interval: 15,
      logger: Rails.logger,
      verbose: :fatal,
      auth_methods: %w[publickey],
      key_data: @keys.map(&:private_key),
      keys: [],
      keys_only: true,                # only the app key, never ~/.ssh/id_*
      use_agent: false
    }
  end
end
