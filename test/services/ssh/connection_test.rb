require "test_helper"

class Ssh::ConnectionTest < ActiveSupport::TestCase
  include TcpHelpers

  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
  end

  teardown do
    FileUtils.rm_rf(@known_hosts.dirname)
  end

  def connect(server, fake, &block)
    Ssh::Connection.open(server, transport: fake, known_hosts_file: @known_hosts, timeout: 5, &block)
  end

  test "connects with the server address, port and username" do
    fake = FakeSsh.new
    connect(servers(:db), fake) { }

    assert_equal "db.example.com", fake.started_with[:host]
    assert_equal "admin", fake.started_with[:user]
    assert_equal 2222, fake.started_with[:port]
    assert_equal 5, fake.started_with[:timeout]
  end

  test "authenticates only with the app SSH key" do
    fake = FakeSsh.new
    connect(servers(:web), fake) { }

    assert_equal %w[publickey], fake.started_with[:auth_methods]
    assert_equal [ ssh_keys(:main).private_key ], fake.started_with[:key_data]
    assert_equal [], fake.started_with[:keys]
    assert fake.started_with[:keys_only]
    assert_equal false, fake.started_with[:use_agent]
    assert_nil fake.started_with[:password]
  end

  test "uses the given key instead of the current one" do
    other = SshKey.new(private_key: "other-private-key")
    fake = FakeSsh.new
    Ssh::Connection.open(servers(:web), key: other, transport: fake, known_hosts_file: @known_hosts) { }

    assert_equal [ "other-private-key" ], fake.started_with[:key_data]
  end

  test "raises MissingKeyError when no SSH key is configured" do
    SshKey.delete_all
    fake = FakeSsh.new

    error = assert_raises(Ssh::Connection::MissingKeyError) { connect(servers(:web), fake) { } }
    assert_match "paramètres", error.message
    assert_nil fake.started_with
  end

  test "never prompts and pins host keys in the app known_hosts file" do
    fake = FakeSsh.new
    connect(servers(:web), fake) { }

    assert fake.started_with[:non_interactive]
    assert_equal false, fake.started_with[:config]
    assert_equal :accept_new, fake.started_with[:verify_host_key]
    assert_equal @known_hosts.to_s, fake.started_with[:user_known_hosts_file]
    assert_equal [], fake.started_with[:global_known_hosts_file]
    assert @known_hosts.dirname.directory?
  end

  test "returns the value of the block" do
    assert_equal :done, connect(servers(:web), FakeSsh.new) { :done }
  end

  test "exec returns stdout, stderr and the exit status separately" do
    fake = FakeSsh.new(responses: { "uname" => FakeSsh::Response.new("Linux\n", "warning\n", 0) })

    result = connect(servers(:web), fake) { |ssh| ssh.exec("uname") }

    assert_equal Ssh::Connection::Result.new(stdout: "Linux\n", stderr: "warning\n", exit_status: 0), result
    assert result.success?
  end

  test "outputs are UTF-8 text, even when an accent is cut between two chunks; bytes that are not UTF-8 are replaced" do
    fake = FakeSsh.new(responses: { "cat" => FakeSsh::Response.new("# Sauvegarde réseau — été\n", "fichier introuvable : é\xFF".b, 1) })

    result = connect(servers(:web), fake) { |ssh| ssh.exec("cat") }

    assert_equal [ Encoding::UTF_8, Encoding::UTF_8 ], [ result.stdout.encoding, result.stderr.encoding ]
    assert_equal "# Sauvegarde réseau — été\n", result.stdout
    assert_equal "fichier introuvable : é\uFFFD", result.stderr
    assert_equal %({"out":"# Sauvegarde réseau — été\\n"}), JSON.generate({ "out" => result.stdout }), "json 3.1 refuses BINARY text with accents"
  end

  test "exec does not raise on a failing command" do
    fake = FakeSsh.new(responses: { "cat /missing" => FakeSsh::Response.new("", "No such file or directory\n", 1) })

    result = connect(servers(:web), fake) { |ssh| ssh.exec("cat /missing") }

    assert_not result.success?
    assert_equal 1, result.exit_status
  end

  test "exec runs several commands in the same session" do
    fake = FakeSsh.new(responses: { "whoami" => FakeSsh::Response.new("deploy\n", "", 0), "hostname" => FakeSsh::Response.new("web\n", "", 0) })

    outputs = connect(servers(:web), fake) { |ssh| [ ssh.exec("whoami").stdout, ssh.exec("hostname").stdout ] }

    assert_equal [ "deploy\n", "web\n" ], outputs
    assert_equal %w[whoami hostname], fake.commands
  end

  test "exec! returns the result of a successful command" do
    fake = FakeSsh.new(responses: { "id -u" => FakeSsh::Response.new("0\n", "", 0) })

    assert_equal "0\n", connect(servers(:web), fake) { |ssh| ssh.exec!("id -u").stdout }
  end

  test "exec! raises CommandError with the result on failure" do
    fake = FakeSsh.new(responses: { "cat /missing" => FakeSsh::Response.new("", "No such file or directory\n", 1) })

    error = assert_raises(Ssh::Connection::CommandError) do
      connect(servers(:web), fake) { |ssh| ssh.exec!("cat /missing") }
    end
    assert_equal "`cat /missing` exited with status 1: No such file or directory", error.message
    assert_equal 1, error.result.exit_status
  end

  test "exec outside of an open session raises" do
    ssh = Ssh::Connection.new(servers(:web), transport: FakeSsh.new)
    assert_raises(Ssh::Connection::Error) { ssh.exec("uname") }
  end

  test "the session is not usable after the block" do
    ssh = connect(servers(:web), FakeSsh.new) { |connection| connection }
    assert_raises(Ssh::Connection::Error) { ssh.exec("uname") }
  end

  test "wraps authentication failures" do
    fake = FakeSsh.new(error: Net::SSH::AuthenticationFailed.new("Authentication failed for user deploy@192.168.1.10"))

    error = assert_raises(Ssh::Connection::AuthenticationError) { connect(servers(:web), fake) { } }
    assert_match "deploy@192.168.1.10", error.message
  end

  test "wraps host key mismatches" do
    mismatch = Net::SSH::HostKeyMismatch.new("fingerprint does not match")
    mismatch.data = { fingerprint: "SHA256:abc" }
    fake = FakeSsh.new(error: mismatch)

    error = assert_raises(Ssh::Connection::HostKeyMismatchError) { connect(servers(:web), fake) { } }
    assert_match "SHA256:abc", error.message
    assert_equal "SHA256:abc", error.new_fingerprint
    assert_equal :host_key_changed, error.reason
  end

  test "a host key mismatch tells which fingerprints were pinned" do
    pinned = Ssh::KeyGenerator.generate
    server = servers(:web)
    FileUtils.mkdir_p(@known_hosts.dirname)
    @known_hosts.write("#{server.port == 22 ? server.host : "[#{server.host}]:#{server.port}"} #{pinned.public_key.split.first(2).join(" ")}\n")
    mismatch = Net::SSH::HostKeyMismatch.new("fingerprint does not match")
    mismatch.data = { fingerprint: "SHA256:new" }

    error = assert_raises(Ssh::Connection::HostKeyMismatchError) { connect(server, FakeSsh.new(error: mismatch)) { } }
    assert_equal [ pinned.fingerprint ], error.known_fingerprints
  end

  test "each error has a French title" do
    assert_equal "Connexion impossible", Ssh::Connection::ConnectionError.new.title
    assert_equal "Clé SSH refusée par le serveur", Ssh::Connection::AuthenticationError.new.title
    assert_equal "L'empreinte du serveur a changé", Ssh::Connection::HostKeyMismatchError.new.title
    assert_equal "Aucune clé SSH configurée", Ssh::Connection::MissingKeyError.new.title
    assert_equal "Erreur SSH", Ssh::Connection::Error.new.title
    assert_equal "Délai dépassé", Ssh::Connection::CommandTimeoutError.new.title
  end

  test "all errors share a common base class" do
    [ Ssh::Connection::ConnectionError, Ssh::Connection::AuthenticationError, Ssh::Connection::HostKeyMismatchError, Ssh::Connection::MissingKeyError, Ssh::Connection::CommandError, Ssh::Connection::CommandTimeoutError ].each do |klass|
      assert_operator klass, :<, Ssh::Connection::Error
    end
  end

  # The tests below go through the real Net::SSH against local sockets.

  test "raises ConnectionError when the port is closed" do
    server = servers(:web)
    server.assign_attributes(host: "127.0.0.1", port: closed_port)

    error = assert_raises(Ssh::Connection::ConnectionError) do
      Ssh::Connection.open(server, known_hosts_file: @known_hosts, timeout: 2) { }
    end
    assert_match "127.0.0.1:#{server.port}", error.message
  end

  test "raises ConnectionError when the host does not speak SSH" do
    with_banner_server("HTTP/1.1 400 Bad Request\r\n\r\n") do |port|
      server = servers(:web)
      server.assign_attributes(host: "127.0.0.1", port: port)

      assert_raises(Ssh::Connection::ConnectionError) do
        Ssh::Connection.open(server, known_hosts_file: @known_hosts, timeout: 2) { }
      end
    end
  end

  test "raises ConnectionError when the host never answers" do
    with_open_port do |port|
      server = servers(:web)
      server.assign_attributes(host: "127.0.0.1", port: port)

      started = Time.current
      assert_raises(Ssh::Connection::ConnectionError) do
        Ssh::Connection.open(server, known_hosts_file: @known_hosts, timeout: 1) { }
      end
      assert_operator Time.current - started, :<, 5
    end
  end

  private

  # Accepts one connection, writes `banner`, then closes it.
  def with_banner_server(banner)
    listener = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      client = listener.accept
      client.write(banner)
      client.close
    rescue IOError
      nil
    end
    yield listener.addr[1]
  ensure
    listener&.close
    thread&.join(1)
  end

  test "tries the active then the pending app key" do
    pending = SshKey.generate_pending!
    fake = FakeSsh.new
    connect(servers(:web), fake) { }

    assert_equal [ ssh_keys(:main).private_key, pending.private_key ], fake.started_with[:key_data]
  end

  test "accepts an explicit list of keys" do
    other = SshKey.new(private_key: "other")
    fake = FakeSsh.new
    Ssh::Connection.open(servers(:web), key: [ other, nil ], transport: fake, known_hosts_file: @known_hosts) { }

    assert_equal [ "other" ], fake.started_with[:key_data]
  end

  test "a command running past its time limit raises and shuts the session down" do
    fake = FakeSsh.new(responses: { "sleep 30" => FakeSsh::Response.new("", "", 0, true), "uname" => FakeSsh::Response.new("Linux\n", "", 0) })
    errors = []

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    connect(servers(:web), fake) do |ssh|
      errors << assert_raises(Ssh::Connection::CommandTimeoutError) { ssh.exec("sleep 30", timeout: 0.2) }
      errors << assert_raises(Ssh::Connection::CommandTimeoutError) { ssh.exec("uname") }
    end

    assert_in_delta 0.2, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 0.5
    assert_match "n'a pas répondu en 0.2 s sur 192.168.1.10 : sleep 30", errors.first.message
    assert_equal "La session a été fermée après un délai dépassé.", errors.last.message
    assert fake.sessions.sole.shut_down?
    assert_equal [ "sleep 30" ], fake.commands
  end

  test "commands get the default time limit of the connection" do
    fake = FakeSsh.new(responses: { "sleep 30" => FakeSsh::Response.new("", "", 0, true) })

    assert_raises(Ssh::Connection::CommandTimeoutError) do
      Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: @known_hosts, command_timeout: 0.1) { |ssh| ssh.exec!("sleep 30") }
    end
  end

  test "keeps whitespace-only output" do
    fake = FakeSsh.new(responses: { "printf '\\n'" => FakeSsh::Response.new("\n", "", 0) })

    assert_equal "\n", connect(servers(:web), fake) { |ssh| ssh.exec("printf '\\n'").stdout }
  end

  test "privilege is :root when logged in as root, without asking" do
    fake = FakeSsh.new

    connect(servers(:backup), fake) do |ssh| # username root
      assert_equal :root, ssh.privilege
      assert ssh.privileged?
      assert_equal "ss -tlnp", ssh.privileged("ss -tlnp")
    end
    assert_empty fake.commands
  end

  test "privilege is :sudo when passwordless sudo works, checked once per session" do
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", 0) })

    connect(servers(:web), fake) do |ssh|
      assert_equal :sudo, ssh.privilege
      assert_equal "sudo -n ss -tlnp", ssh.privileged("ss -tlnp")
    end
    assert_equal [ "sudo -n true" ], fake.commands
  end

  test "privilege is :none without passwordless sudo" do
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "sudo: a password is required\n", 1) })

    connect(servers(:web), fake) do |ssh|
      assert_equal :none, ssh.privilege
      assert_not ssh.privileged?
      assert_equal "ss -tln", ssh.privileged("ss -tln")
    end
  end

  test "run_command: the variant of the distribution, read once per session and only when needed" do
    fake = FakeSsh.new(handler: lambda { |command|
      if command.start_with?(". /etc/os-release") then FakeSsh::Response.new("ubuntu debian\n", "", 0)
      else FakeSsh::Response.new("ok", "", 0)
      end
    })
    connect(servers(:web), fake) do |ssh|
      ssh.run_command("inventory.os")
      2.times { ssh.run_command("inventory.health") }
      assert_equal %w[ubuntu debian], ssh.distros
    end

    os_release, os, health, health_again = fake.commands
    assert_equal Ssh::Commands.render("inventory.os"), os_release, "inventory.os has no variant: no os-release read before it"
    assert_equal Ssh::Commands.render("connection.os_release"), os
    assert_equal Ssh::Commands.render("inventory.health", distros: %w[ubuntu debian]), health
    assert_equal health, health_again
  end

  test "run_command: root commands through sudo, values escaped, an unknown system gets the default variant" do
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", 0) })
    connect(servers(:web), fake) do |ssh|
      ssh.run_command("inventory.ports")
      ssh.run_command("connection.check", token: "a b")
      ssh.run_command("inventory.packages")
    end

    assert_includes fake.commands, "sudo -n #{Ssh::Commands.render("inventory.ports")}"
    assert_includes fake.commands, "echo a\\ b"
    assert_includes fake.commands, Ssh::Commands.render("inventory.packages")
  end

  test "run_command! raises with the name of the command" do
    error = assert_raises(Ssh::Connection::CommandError) { connect(servers(:web), FakeSsh.new) { |ssh| ssh.run_command!("keys.read") } }
    assert_match(/\A`keys.read` exited with status 127/, error.message)
  end
end
