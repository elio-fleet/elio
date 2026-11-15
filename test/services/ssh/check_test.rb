require "test_helper"

class Ssh::CheckTest < ActiveSupport::TestCase
  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
  end

  teardown do
    FileUtils.rm_rf(@known_hosts.dirname)
  end

  def check(fake, server: servers(:web))
    Ssh::Check.call(server, transport: fake, known_hosts_file: @known_hosts)
  end

  def echo_handler
    ->(command) { FakeSsh::Response.new("#{command.delete_prefix("echo ")}\n", "", 0) if command.start_with?("echo ") }
  end

  test "succeeds when the server echoes the token back" do
    fake = FakeSsh.new(handler: echo_handler)

    result = check(fake)

    assert result.success?
    assert_equal "Connexion SSH réussie", result.message
    assert_match "deploy@192.168.1.10", result.details
    assert_match(/\Aecho elio-check-\h{8}\z/, fake.commands.sole)
  end

  test "with privilege, also probes sudo -n once the login works" do
    without = FakeSsh.new(handler: echo_handler, responses: { "sudo -n true" => FakeSsh::Response.new("", "a password is required\n", 1) })
    with = FakeSsh.new(handler: echo_handler, responses: { "sudo -n true" => FakeSsh::Response.new("", "", 0) })

    assert_equal "none", Ssh::Check.call(servers(:web), privilege: true, transport: without, known_hosts_file: @known_hosts).privilege
    assert_equal "sudo", Ssh::Check.call(servers(:web), privilege: true, transport: with, known_hosts_file: @known_hosts).privilege
    assert_nil check(with).privilege, "not probed unless asked"
    assert_equal 3, with.commands.size
  end

  test "uses a different token on each call" do
    fake = FakeSsh.new(handler: echo_handler)

    2.times { check(fake) }

    assert_equal 2, fake.commands.uniq.size
  end

  test "runs on a connection already open instead of opening one" do
    fake = FakeSsh.new(handler: echo_handler)

    result = Ssh::Connection.open(servers(:web), transport: fake, known_hosts_file: @known_hosts) { |ssh| Ssh::Check.call(servers(:web), ssh: ssh) }

    assert result.success?
    assert_equal 1, fake.sessions.size
  end

  test "fails when the output does not match the token" do
    fake = FakeSsh.new(handler: ->(_command) { FakeSsh::Response.new("Welcome!\n", "", 0) })

    result = check(fake)

    assert_not result.success?
    assert_equal "Réponse inattendue du serveur", result.message
    assert_match "Welcome!", result.details
  end

  test "fails when the command exits with an error" do
    fake = FakeSsh.new(handler: ->(_command) { FakeSsh::Response.new("", "restricted shell\n", 1) })

    result = check(fake)

    assert_not result.success?
    assert_equal "La commande a échoué", result.message
    assert_match "restricted shell", result.details
  end

  test "explains when no SSH key is configured" do
    SshKey.delete_all

    result = check(FakeSsh.new)

    assert_not result.success?
    assert_equal "Aucune clé SSH configurée", result.message
  end

  test "explains when the key is refused" do
    result = check(FakeSsh.new(error: Net::SSH::AuthenticationFailed.new("Authentication failed for user deploy@192.168.1.10")))

    assert_not result.success?
    assert_equal "Clé SSH refusée par le serveur", result.message
    assert_match "deploy@192.168.1.10", result.details
  end

  test "explains when the host key changed" do
    mismatch = Net::SSH::HostKeyMismatch.new("mismatch")
    mismatch.data = { fingerprint: "SHA256:abc" }

    result = check(FakeSsh.new(error: mismatch))

    assert_equal "L'empreinte du serveur a changé", result.message
    assert_equal :host_key_changed, result.reason
    assert_equal "SHA256:abc", result.host_key[:new]
    assert_equal [], result.host_key[:known]
    assert_not result.host_key[:new_algorithm], "nothing was pinned to compare with"
  end

  test "explains when the server cannot be reached" do
    result = check(FakeSsh.new(error: Errno::ECONNREFUSED.new))

    assert_not result.success?
    assert_equal "Connexion impossible", result.message
    assert_match "192.168.1.10:22", result.details
  end
end
