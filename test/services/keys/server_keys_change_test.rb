require "test_helper"

class Keys::ServerKeysChangeTest < ActiveSupport::TestCase
  include LocalShellHelpers
  include StubHelpers

  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
    setup_temp_home
    @server = servers(:web)
    @login = AuthorizedKeysAccount.login(@server)
    @public_key = public_keys(:alice)
  end

  teardown do
    FileUtils.rm_rf(@known_hosts.dirname)
    teardown_temp_home
  end

  # Runs the commands for real in the temporary HOME; no sudo (the login account only).
  def fake_server = FakeSsh.new(handler: ->(command) { command == "sudo -n true" ? FakeSsh::Response.new("", "", 1) : local_shell.call(command) })

  def options = { transport: @fake, known_hosts_file: @known_hosts }

  test "adds the key, then reads every account back, on a single connection" do
    @fake = fake_server

    change = Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login ], **options)

    account, result = change.outcomes.sole
    assert_equal @login, account
    assert result.added?
    assert_equal 1, @fake.sessions.size
    assert_equal [ @public_key.fingerprint ], change.read.login.keys.map(&:fingerprint)
    assert Activity.of_kind(:key_added).exists?(server: @server)
  end

  test "writes the restrictions in front of the key, quoted" do
    @fake = fake_server
    key_options = KeyOptions.new(from: "10.0.0.0/8", command: %(echo "$(id)" 'x'), no_port_forwarding: true)

    Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login ], options: key_options, **options)

    key = AuthorizedKey.parse(authorized_keys_file.read).sole
    assert_equal %(from="10.0.0.0/8",command="echo \\"$(id)\\" 'x'",no-port-forwarding), key.options
    assert_equal @public_key.fingerprint, key.fingerprint
    assert_equal %(from="10.0.0.0/8",command="echo \\"$(id)\\" 'x'",no-port-forwarding), Activity.of_kind(:key_added).sole.data["options"]
  end

  test "a key that is not there when read back is reported, not added" do
    @fake = FakeSsh.new(handler: lambda { |command|
      next FakeSsh::Response.new("", "", 1) if command == "sudo -n true"
      next FakeSsh::Response.new("added\n", "", 0) if command.include?("printf")

      local_shell.call(command)
    })

    result = Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login ], **options).outcomes.sole.last

    assert_not result.success?
    assert_equal "Clé introuvable après l'écriture", result.error_title
    assert_match "deploy", result.error_details
  end

  test "removes the key and reads the accounts back on the same connection" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("#{@public_key.content} Alice\n")
    @fake = fake_server

    change = Keys::ServerKeysChange.revoke(@server, @public_key.authorized_key.key, account: @login, key_name: "Alice", **options)

    assert change.outcomes.sole.last.removed?
    assert_equal 1, @fake.sessions.size
    assert_empty change.read.login.keys
    assert_equal "", authorized_keys_file.read
  end

  test "a key still there after its removal is reported" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("#{@public_key.content} Alice\n")
    @fake = FakeSsh.new(handler: lambda { |command|
      next FakeSsh::Response.new("", "", 1) if command == "sudo -n true"
      next FakeSsh::Response.new("removed\n", "", 0) if command.include?("mktemp")

      local_shell.call(command)
    })

    result = Keys::ServerKeysChange.revoke(@server, @public_key.authorized_key.key, account: @login, **options).outcomes.sole.last

    assert_not result.success?
    assert_equal "Clé toujours présente", result.error_title
  end

  test "Elio's own key is refused without connecting" do
    @fake = FakeSsh.new(error: RuntimeError.new("no connection expected"))

    change = Keys::ServerKeysChange.revoke(@server, ssh_keys(:main).blob, account: @login, **options)

    assert_equal "Suppression interdite", change.outcomes.sole.last.error_title
    assert_nil change.read
  end

  test "a connection that fails is the error of every account and of the read" do
    @fake = FakeSsh.new(error: Errno::ECONNREFUSED.new)
    root = AuthorizedKeysAccount.for(@server, "root")

    change = Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login, root ], **options)

    assert_equal [ "Connexion impossible" ] * 2, change.outcomes.map { |_account, result| result.error_title }
    assert_not change.read.success?
  end

  test "an account that could not be written keeps its own error, the others go on" do
    @fake = fake_server
    root = AuthorizedKeysAccount.for(@server, "root")

    change = Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login, root ], **options)

    assert change.outcomes.first.last.added?
    assert_equal "Root nécessaire", change.outcomes.last.last.error_title
    assert_equal 1, @fake.sessions.size
  end

  test "runs under the server's key lock" do
    @fake = fake_server
    held = []
    stub_method(AdvisoryLock, :hold, ->(name, &block) { held << name; block.call }) do
      Keys::ServerKeysChange.grant(@server, @public_key, accounts: [ @login ], **options)
    end

    assert_equal [ "authorized_keys:server:#{@server.id}" ], held
  end
end
