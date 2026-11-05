require "test_helper"

# The keys of every account of a server, read and removed through root
# (phase 13.4). The scripts run for real with sh, with a fake `getent` that
# lists accounts whose homes are in a temporary directory.
class Keys::AuthorizedKeysAccountsTest < ActiveSupport::TestCase
  include LocalShellHelpers

  Reader = Keys::AuthorizedKeysReader

  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
    setup_temp_home
    @root = Pathname(Dir.mktmpdir)
    @bin = @root.join("bin").tap(&:mkpath)
    @alice_key = Ssh::KeyGenerator.generate(comment: "alice").public_key.strip
    @bob_key = Ssh::KeyGenerator.generate(comment: "bob").public_key.strip
    { "root" => "/bin/bash", "bob" => "/bin/sh", "daemon" => "/usr/sbin/nologin", "carol" => "/bin/bash", "dave" => "/bin/bash" }.each_with_index do |(user, shell), uid|
      @root.join(user).mkpath
      (@passwd ||= +"") << "#{user}:x:#{uid}:#{uid}::#{@root.join(user)}:#{shell}\n"
    end
    write_keys("root", @alice_key)
    write_keys("bob", "# deploy\n#{@bob_key}\n#{@alice_key}")
    write_keys("daemon", @alice_key) # no login shell: skipped
    write_keys("carol", @alice_key).chmod(0o000) # unreadable
    # dave: no file, skipped
    @bin.join("getent").write(<<~SH)
      #!/bin/sh
      [ "$1" = passwd ] || exit 2
      if [ -n "$2" ]; then grep "^$2:" "#{@root.join("passwd")}" || exit 2; else cat "#{@root.join("passwd")}"; fi
    SH
    @bin.join("getent").chmod(0o755)
    @root.join("passwd").write(@passwd)
  end

  teardown do
    FileUtils.chmod_R(0o755, @root)
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@known_hosts.dirname)
    teardown_temp_home
  end

  def write_keys(user, content)
    @root.join(user, ".ssh").mkpath
    @root.join(user, ".ssh", "authorized_keys").tap { |file| file.write("#{content}\n") }
  end

  def run_with_getent(script)
    stdout, stderr, status = Open3.capture3({ "HOME" => @home.to_s, "PATH" => "#{@bin}:#{ENV["PATH"]}" }, "sh", "-c", script)
    [ stdout, stderr, status.exitstatus ]
  end

  # A server reached through sudo: the probe succeeds, `sudo -n …` runs as is locally.
  def fake(sudo: true)
    FakeSsh.new(handler: lambda { |command|
      next FakeSsh::Response.new("", sudo ? "" : "sudo: a password is required\n", sudo ? 0 : 1) if command == "sudo -n true"

      stdout, stderr, status = run_with_getent(command.delete_prefix("sudo -n "))
      FakeSsh::Response.new(stdout, stderr, status)
    })
  end

  test "the script lists the accounts with a login shell and a file, and flags an unreadable one" do
    stdout, _, status = run_with_getent(Reader.accounts_command)
    assert_equal 0, status
    accounts = Reader.parse_accounts(stdout)

    assert_equal %w[root bob carol], accounts.keys
    assert_equal [ "alice" ], AuthorizedKey.parse(accounts["root"].first).map(&:name)
    assert_equal %w[bob alice], AuthorizedKey.parse(accounts["bob"].first).map(&:name)
    assert_equal [ "", true ], accounts["carol"]
  end

  test "call_all reads the login account, then the others through root" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("#{ssh_keys(:main).public_key}\n")

    read = Reader.call_all(servers(:web), transport: fake, known_hosts_file: @known_hosts)

    assert read.success?
    assert read.privileged
    assert_equal %w[deploy root bob carol], read.accounts.map { |entry| entry.account.unix_user }
    assert read.login.account.login?
    assert_equal [ "elio-fixture" ], read.login.keys.map(&:name)
    assert read.accounts.last.unreadable
    assert_equal 4, read.keys.size
  end

  test "without root, only the login account" do
    read = Reader.call_all(servers(:web), transport: fake(sudo: false), known_hosts_file: @known_hosts)

    assert read.success?
    assert_not read.privileged
    assert_equal %w[deploy], read.accounts.map { |entry| entry.account.unix_user }
  end

  test "the login account is not listed twice when Elio logs in as root" do
    read = Reader.call_all(servers(:backup), transport: fake, known_hosts_file: @known_hosts)
    assert_equal %w[root bob carol], read.accounts.map { |entry| entry.account.unix_user }
  end

  test "removing a key from another account keeps the other lines, the owner and the rights" do
    file = @root.join("bob", ".ssh", "authorized_keys")
    file.chmod(0o600)
    blob = @alice_key.split[1]

    result = Keys::AuthorizedKeyRemoval.call(servers(:web), blob, account: AuthorizedKeysAccount.new(servers(:web), "bob"), transport: fake, known_hosts_file: @known_hosts)

    assert result.removed?
    assert_equal "# deploy\n#{@bob_key}\n", file.read
    assert_equal 0o600, file.stat.mode & 0o777
    assert_empty Dir.glob(@root.join("bob", ".ssh", "authorized_keys.*").to_s)

    again = Keys::AuthorizedKeyRemoval.call(servers(:web), blob, account: AuthorizedKeysAccount.new(servers(:web), "bob"), transport: fake, known_hosts_file: @known_hosts)
    assert again.absent?
  end

  test "removing from another account needs root, an unknown account fails, Elio's key is protected" do
    blob = @alice_key.split[1]
    bob = AuthorizedKeysAccount.new(servers(:web), "bob")

    refused = Keys::AuthorizedKeyRemoval.call(servers(:web), blob, account: bob, transport: fake(sudo: false), known_hosts_file: @known_hosts)
    assert_equal :error, refused.status
    assert_equal "Root nécessaire", refused.error_title
    assert_includes @root.join("bob", ".ssh", "authorized_keys").read, blob

    unknown = Keys::AuthorizedKeyRemoval.call(servers(:web), blob, account: AuthorizedKeysAccount.new(servers(:web), "nobody"), transport: fake, known_hosts_file: @known_hosts)
    assert_equal :error, unknown.status

    protected_key = Keys::AuthorizedKeyRemoval.call(servers(:web), ssh_keys(:main).public_key.split[1], account: bob, transport: fake, known_hosts_file: @known_hosts)
    assert_equal :error, protected_key.status
    assert_equal "Suppression interdite", protected_key.error_title
  end

  test "an account name from a request is checked" do
    assert AuthorizedKeysAccount.for(servers(:web), "").login?
    assert AuthorizedKeysAccount.for(servers(:web), "deploy").login?
    assert_equal "root", AuthorizedKeysAccount.for(servers(:web), "root").unix_user
    assert_nil AuthorizedKeysAccount.for(servers(:web), "bob; rm -rf /")
    assert_nil AuthorizedKeysAccount.for(servers(:web), "../etc")
  end

  test "snapshots: every account is recorded, the vanished ones dropped only with root" do
    server = servers(:web)
    AccountSnapshot.create!(server: server, unix_user: "old", content: @alice_key, read_at: 1.day.ago)
    read = Reader.call_all(server, transport: fake(sudo: false), known_hosts_file: @known_hosts)
    AccountSnapshot.record_all!(server, read)
    assert_equal %w[deploy old], server.account_snapshots.order(:unix_user).pluck(:unix_user)

    read = Reader.call_all(server, transport: fake, known_hosts_file: @known_hosts)
    AccountSnapshot.record_all!(server, read)
    assert_equal %w[bob deploy root], server.account_snapshots.order(:unix_user).pluck(:unix_user), "carol unreadable: not recorded, old: gone"
    assert Activity.of_kind(:unknown_key_detected).where(server: server, unix_user: "bob").exists?
  end
end
