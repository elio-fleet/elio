require "test_helper"

class Ssh::DiagnosisTest < ActiveSupport::TestCase
  include TcpHelpers

  setup do
    @dir = Dir.mktmpdir
    @known_hosts = Pathname(@dir).join("known_hosts")
    @listeners = []
  end

  teardown do
    @listeners.each { |listener, thread| thread.kill && listener.close }
    FileUtils.rm_rf(@dir)
  end

  # A local port whose service writes `greeting` (nil: nothing) to each client, then stays silent.
  def listening(greeting)
    listener = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        client = listener.accept
        client.write(greeting) if greeting
        Thread.new { client.read rescue nil }
      end
    end
    @listeners << [ listener, thread ]
    listener.addr[1]
  end

  def server(port, host: "127.0.0.1", username: "deploy")
    servers(:web).tap { |server| server.assign_attributes(host: host, port: port, username: username) }
  end

  def echo_handler(sudo: 0)
    lambda do |command|
      if command.start_with?("echo ") then FakeSsh::Response.new("#{command.delete_prefix("echo ")}\n", "", 0)
      elsif command == "sudo -n true" then FakeSsh::Response.new("", sudo.zero? ? "" : "a password is required\n", sudo)
      end
    end
  end

  def diagnose(server, transport: FakeSsh.new(handler: echo_handler), **options)
    Ssh::Diagnosis.call(server, timeout: 0.3, transport: transport, known_hosts_file: @known_hosts, **options)
  end

  def statuses(result) = result.steps.to_h { |step| [ step.key, step.status ] }

  test "every step passes on a server Elio can log in to with sudo" do
    result = diagnose(server(listening("SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13\r\n")))

    assert result.success?
    assert_equal Ssh::Diagnosis::STEPS.index_with(:ok), statuses(result)
    steps = result.steps.index_by(&:key)
    assert_equal "Une adresse IP, rien à résoudre.", steps[:dns].detail
    assert_equal "SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13", steps[:banner].detail
    assert_match "Première connexion", steps[:host_key].detail
    assert_equal "Connecté en tant que deploy.", steps[:authentication].detail
    assert_nil result.steps.filter_map(&:fix).first
  end

  test "lines before the SSH banner are allowed" do
    result = diagnose(server(listening("Welcome\r\nSSH-2.0-OpenSSH_9.2\r\n")))

    assert_equal "SSH-2.0-OpenSSH_9.2", result.steps.find { |step| step.key == :banner }.detail
  end

  test "a host name that does not resolve stops at the first step" do
    result = diagnose(server(22, host: "nowhere.invalid"), resolver: ->(_host) { raise SocketError, "getaddrinfo: nodename nor servname provided" })

    assert_equal({ dns: :failed, tcp: :skipped, banner: :skipped, host_key: :skipped, authentication: :skipped, sudo: :skipped }, statuses(result))
    assert_equal :dns, result.failed_step.fix
    assert_match "nodename", result.failed_step.detail
  end

  test "a resolved host name lists its addresses" do
    port = listening("SSH-2.0-OpenSSH_9.6\r\n")
    result = diagnose(server(port, host: "web.example"), resolver: ->(host) { host == "web.example" ? [ "127.0.0.1" ] : [] })

    assert result.success?
    assert_equal "Adresses : 127.0.0.1", result.steps.first.detail
  end

  test "a closed port says to check the port and the SSH server" do
    result = diagnose(server(closed_port))

    assert_equal :tcp, result.failed_step.key
    assert_equal :port_refused, result.failed_step.fix
    assert_equal :skipped, statuses(result)[:banner]
  end

  test "another service on the port is not taken for an SSH server" do
    result = diagnose(server(listening("HTTP/1.1 400 Bad Request\r\n" * 6)))

    assert_equal :banner, result.failed_step.key
    assert_equal :not_ssh, result.failed_step.fix
    assert_match "HTTP/1.1 400", result.failed_step.detail
  end

  test "a silent service fails at the banner, quickly" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = diagnose(server(listening(nil)))

    assert_equal :banner_silent, result.failed_step.fix
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  test "a refused key fails at the login, after the host key, with the key hint" do
    refused = FakeSsh.new(error: Net::SSH::AuthenticationFailed.new("Authentication failed for user deploy@127.0.0.1"))
    result = diagnose(server(listening("SSH-2.0-OpenSSH_9.6\r\n")), transport: refused)

    assert_equal :ok, statuses(result)[:host_key]
    assert_equal :authentication, result.failed_step.key
    assert_equal :key_refused, result.failed_step.reason
    assert_equal :skipped, statuses(result)[:sudo]
  end

  test "a changed host key fails at the host key, with both fingerprints" do
    mismatch = Net::SSH::HostKeyMismatch.new("mismatch")
    mismatch.data = { fingerprint: "SHA256:abc" }
    result = diagnose(server(listening("SSH-2.0-OpenSSH_9.6\r\n")), transport: FakeSsh.new(error: mismatch))

    assert_equal :host_key, result.failed_step.key
    assert_equal :host_key_changed, result.failed_step.reason
    assert_equal "SHA256:abc", result.failed_step.host_key[:new]
    assert_equal :skipped, statuses(result)[:authentication]
  end

  test "without Elio's key, the login step says to generate it" do
    SshKey.delete_all
    result = Ssh::Diagnosis.call(server(listening("SSH-2.0-OpenSSH_9.6\r\n")), timeout: 0.3, transport: FakeSsh.new, known_hosts_file: @known_hosts)

    assert_equal :skipped, statuses(result)[:host_key]
    assert_equal :missing_key, result.failed_step.reason
  end

  test "without sudo, the root access step warns and says what the inventory misses" do
    result = diagnose(server(listening("SSH-2.0-OpenSSH_9.6\r\n")), transport: FakeSsh.new(handler: echo_handler(sudo: 1)))

    assert result.success?, "a limit, not a failure"
    sudo = result.steps.last
    assert_equal :warn, sudo.status
    assert_equal :sudo, sudo.fix
  end

  test "logged in as root, sudo is not probed" do
    transport = FakeSsh.new(handler: echo_handler(sudo: 1))
    result = diagnose(server(listening("SSH-2.0-OpenSSH_9.6\r\n"), username: "root"), transport: transport)

    assert_equal "Connecté en root.", result.steps.last.detail
    assert_not_includes transport.commands, "sudo -n true"
  end
end
