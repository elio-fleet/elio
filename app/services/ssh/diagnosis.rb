require "ipaddr"
require "socket"

# Step-by-step diagnosis of the SSH access to a server, to tell which step
# fails and what to do about it: name lookup, TCP port, SSH banner, host key,
# login with Elio's key (Ssh::Check), then root access (sudo -n).
#
#   Ssh::Diagnosis.call(server).steps # => [Step(key: :dns, status: :ok, …), …]
#
# Each step only runs when the previous ones passed (the others are
# :skipped). Short delays: a diagnosis answers in seconds even when the
# server is down. Read-only: the TCP probe only reads the banner, the SSH
# steps run the commands of the login test and of the sudo probe.
# `resolver`: (host) -> list of addresses, swappable in tests;
# `connection_options` go to Ssh::Connection (transport, known_hosts_file).
class Ssh::Diagnosis
  STEPS = %i[dns tcp banner host_key authentication sudo].freeze
  TIMEOUT = 5 # seconds, per step
  BANNER_LINES = 5 # lines a server may send before its "SSH-" line (RFC 4253)

  # status: :ok, :warn (works, with a limit), :failed or :skipped.
  # fix: key of ssh.diagnosis.fixes (with host, port, username); reason / host_key: as in
  # Ssh::Check::Result, for the key install hint and the host key review.
  Step = Data.define(:key, :status, :detail, :fix, :reason, :host_key) do
    def initialize(key:, status:, detail: nil, fix: nil, reason: nil, host_key: nil) = super
    def failed? = status == :failed
  end

  Result = Data.define(:steps) do
    def failed_step = steps.find(&:failed?)
    def success? = failed_step.nil?
  end

  DEFAULT_RESOLVER = ->(host) { Addrinfo.getaddrinfo(host, nil, nil, :STREAM, timeout: TIMEOUT).map(&:ip_address).uniq }

  def self.call(server, **options) = new(server, **options).call

  def initialize(server, timeout: TIMEOUT, resolver: DEFAULT_RESOLVER, **connection_options)
    @server = server
    @timeout = timeout
    @resolver = resolver
    @connection_options = connection_options
    @steps = []
  end

  def call
    addresses = resolve
    socket = connect(addresses) if addresses
    read_banner(socket) if socket
    log_in if @steps.none?(&:failed?)
    Result.new(steps: STEPS.map { |key| @steps.find { |step| step.key == key } || Step.new(key: key, status: :skipped) })
  ensure
    socket&.close
  end

  private

  attr_reader :server

  def add(key, status, detail = nil, **options)
    @steps << Step.new(key: key, status: status, detail: detail, **options)
  end

  def t(key, **params) = I18n.t("ssh.diagnosis.details.#{key}", **params)

  # Addresses of the host (itself when it is already an IP address).
  def resolve
    if ip_address?(server.host)
      add(:dns, :ok, t(:ip_address))
      return [ server.host ]
    end

    addresses = @resolver.call(server.host)
    raise SocketError, "no address" if addresses.empty?

    add(:dns, :ok, t(:resolved, addresses: addresses.first(3).join(", ")))
    addresses
  rescue SocketError, SystemCallError, IO::TimeoutError, Timeout::Error => e
    add(:dns, :failed, t(:error, message: e.message), fix: :dns)
    nil
  end

  # An open TCP connection to the SSH port (the first address that answers).
  def connect(addresses)
    error = nil
    addresses.each do |address|
      socket = Socket.tcp(address, server.port, connect_timeout: @timeout)
      socket.remote_address # raises when the connection was in fact refused (see Servers::Ping)
      add(:tcp, :ok, t(:connected, address: address, port: server.port))
      return socket
    rescue SystemCallError, SocketError, IO::TimeoutError, Timeout::Error => e
      socket&.close
      error = e
    end
    fix = error.is_a?(Errno::ECONNREFUSED) ? :port_refused : :port_silent
    add(:tcp, :failed, t(:error, message: error.message), fix: fix)
    nil
  end

  # An SSH server speaks first: "SSH-2.0-OpenSSH_9.6…" (maybe after a few
  # lines of text). Nothing is sent to it.
  def read_banner(socket)
    first = nil
    BANNER_LINES.times do
      return add(:banner, :failed, t(:no_banner, timeout: @timeout), fix: :banner_silent) unless socket.wait_readable(@timeout)

      line = socket.gets("\n", 255)
      return add(:banner, :failed, t(:closed), fix: :banner_closed) if line.nil?

      line = line.scrub.strip
      return add(:banner, :ok, line.truncate(120)) if line.start_with?("SSH-")

      first ||= line
    end
    add(:banner, :failed, t(:not_ssh, received: first.truncate(80)), fix: :not_ssh)
  rescue SystemCallError, IOError => e
    add(:banner, :failed, t(:error, message: e.message), fix: :banner_closed)
  end

  # Host key, login with Elio's key and root access, in one SSH session.
  def log_in
    known = Ssh::KnownHosts.entries(server.host, server.port, file: known_hosts_file)
    Ssh::Connection.open(server, timeout: @timeout, **@connection_options) do |ssh|
      add(:host_key, :ok, host_key_detail(known))
      check = Ssh::Check.call(server, ssh: ssh)
      next add(:authentication, :failed, check.details, fix: :command) unless check.success?

      add(:authentication, :ok, t(:logged_in, username: server.username))
      add_sudo(ssh.privilege)
    end
  rescue Ssh::Connection::HostKeyMismatchError => e
    add(:host_key, :failed, e.message, reason: e.reason, host_key: { new: e.new_fingerprint, new_type: e.new_type, known: e.known, new_algorithm: e.new_algorithm? })
  rescue Ssh::Connection::MissingKeyError, Ssh::Connection::AuthenticationError => e
    add(:host_key, :ok, host_key_detail(known)) if e.is_a?(Ssh::Connection::AuthenticationError)
    add(:authentication, :failed, e.message, reason: e.reason)
  rescue Ssh::Connection::Error => e
    # Before the session (key exchange) or inside it (the sudo probe timed out).
    step = STEPS.find { |key| @steps.none? { |done| done.key == key } }
    add(step, :failed, e.message, fix: (:handshake if step == :host_key))
  end

  def host_key_detail(known_before)
    entries = Ssh::KnownHosts.entries(server.host, server.port, file: known_hosts_file)
    fingerprints = entries.map { |entry| "#{entry.type} #{entry.fingerprint}" }.join(", ")
    t(known_before.empty? ? :host_key_pinned : :host_key_known, fingerprints: fingerprints)
  end

  def add_sudo(privilege)
    case privilege
    when :root then add(:sudo, :ok, t(:root))
    when :sudo then add(:sudo, :ok, t(:sudo))
    else add(:sudo, :warn, t(:no_sudo, username: server.username), fix: :sudo)
    end
  end

  def known_hosts_file = @connection_options[:known_hosts_file] || Ssh::KnownHosts.file

  def ip_address?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::Error
    false
  end
end
