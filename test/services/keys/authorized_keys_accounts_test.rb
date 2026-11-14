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
    { "root" => "/bin/bash", "bob" => "/bin/sh", "daemon" => "/usr/sbin/nologin", "carol" => "/bin/bash", "dave" => "/bin/bash", "mallory" => "/bin/bash", "eve" => "/bin/bash" }.each_with_index do |(user, shell), uid|
      @root.join(user).mkpath
      (@passwd ||= +"") << "#{user}:x:#{uid}:#{uid}::#{@root.join(user)}:#{shell}\n"
    end
    write_keys("root", @alice_key)
    write_keys("bob", "# deploy\n#{@bob_key}\n#{@alice_key}")
    write_keys("daemon", @alice_key) # no login shell: skipped
    write_keys("carol", @alice_key).chmod(0o000) # unreadable
    # mallory links her file to root's, eve's file belongs to root: both refused.
    @root.join("mallory", ".ssh").mkpath
    File.symlink(@root.join("root", ".ssh", "authorized_keys"), @root.join("mallory", ".ssh", "authorized_keys"))
    write_keys("eve", @alice_key)
    # dave: no file, skipped
    @bin.join("getent").write(<<~SH)
      #!/bin/sh
      [ "$1" = passwd ] || exit 2
      if [ -n "$2" ]; then grep "^$2:" "#{@root.join("passwd")}" || exit 2; else cat "#{@root.join("passwd")}"; fi
    SH
    @bin.join("getent").chmod(0o755)
    # Owner of a file = the account whose home holds it (the files belong to the test runner),
    # except eve's file, which belongs to root.
    @bin.join("ls").write(<<~SH)
      #!/bin/sh
      path="$2"; account=$(echo "$path" | sed "s#^#{@root}/##; s#/.*##")
      [ "$account" = eve ] && account=root
      echo "-rw------- 1 $account $account 0 Jan 1 00:00 $path"
    SH
    @bin.join("ls").chmod(0o755)
    # The file is read and written as the account (`runuser -u <account> -- …`): the test runner is every account here.
    @bin.join("runuser").write(<<~SH)
      #!/bin/sh
      [ "$1" = -u ] && [ "$3" = -- ] || exit 2
      echo "$2" >> "#{@root.join("runuser.log")}"
      shift 3
      exec "$@"
    SH
    @bin.join("runuser").chmod(0o755)
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

    assert_equal %w[root bob carol mallory eve], accounts.keys
    assert_equal [ "alice" ], AuthorizedKey.parse(accounts["root"].first).map(&:name)
    assert_equal %w[bob alice], AuthorizedKey.parse(accounts["bob"].first).map(&:name)
    assert_equal [ "", true ], accounts["carol"]
    assert_equal [ "", true ], accounts["mallory"], "a link to root's file is not read as root"
    assert_equal [ "", true ], accounts["eve"], "a file the account does not own is not read"
  end

  test "call_all reads the login account, then the others through root" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("#{ssh_keys(:main).public_key}\n")

    read = Reader.call_all(servers(:web), transport: fake, known_hosts_file: @known_hosts)

    assert read.success?
    assert read.privileged
    assert_equal %w[deploy root bob carol eve mallory], read.accounts.map { |entry| entry.account.unix_user }
    assert read.login.account.login?
    assert_equal [ "elio-fixture" ], read.login.keys.map(&:name)
    assert read.accounts.last(3).all?(&:unreadable)
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
    assert_equal %w[root bob carol eve mallory], read.accounts.map { |entry| entry.account.unix_user }
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

  test "removal never writes through a link nor in a file the account does not own" do
    root_file = @root.join("root", ".ssh", "authorized_keys")
    root_file.write("#{@alice_key}\n#{@bob_key}\n")
    before = root_file.read
    [ "mallory", "eve" ].each do |user|
      result = Keys::AuthorizedKeyRemoval.call(servers(:web), @alice_key.split[1], account: AuthorizedKeysAccount.new(servers(:web), user), transport: fake, known_hosts_file: @known_hosts)
      assert_equal :error, result.status, user
    end
    assert_equal before, root_file.read, "root's file is untouched"
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

  # The test runner cannot give a file to another account: chown is a no-op here.
  def without_chown = @bin.join("chown").tap { |file| file.write("#!/bin/sh\nexit 0\n") }.chmod(0o755)

  def authorize(user, public_key: public_keys(:alice), sudo: true, **options)
    Keys::PublicKeyAuthorization.call(servers(:web), public_key, account: AuthorizedKeysAccount.new(servers(:web), user), transport: fake(sudo: sudo),
                                                                 known_hosts_file: @known_hosts, **options)
  end

  test "adding a key to another account keeps its lines; a second time it is already there" do
    without_chown
    file = @root.join("bob", ".ssh", "authorized_keys")

    assert authorize("bob").added?
    assert_equal "# deploy\n#{@bob_key}\n#{@alice_key}\n#{public_keys(:alice).content.split.first(2).join(" ")} Alice\n", file.read
    assert authorize("bob").already_present?
  end

  test "adding a key to an account without ~/.ssh creates it, private; never the account" do
    without_chown

    assert authorize("dave").added?
    assert_equal 0o700, @root.join("dave", ".ssh").stat.mode & 0o777
    assert_equal 0o600, @root.join("dave", ".ssh", "authorized_keys").stat.mode & 0o777
    assert_equal "Alice", AuthorizedKey.parse(@root.join("dave", ".ssh", "authorized_keys").read).sole.name

    unknown = authorize("nobody")
    assert_equal [ :error, "Compte inconnu" ], [ unknown.status, unknown.error_title ]
    assert_not @root.join("nobody").exist?
  end

  test "the files of another account are read and written as that account, never as root" do
    authorize("bob")
    Keys::AuthorizedKeyRemoval.call(servers(:web), @alice_key.split[1], account: AuthorizedKeysAccount.new(servers(:web), "bob"), transport: fake, known_hosts_file: @known_hosts)
    run_with_getent(Reader.accounts_command)

    runs = @root.join("runuser.log").readlines(chomp: true)
    assert_includes runs, "bob"
    assert_includes runs, "root", "root's own file is read as root"
    assert_equal %w[bob carol root], runs.uniq.sort, "each file read as its own account, mallory's link and eve's file never opened"
    %w[append_to_account replace_in_account remove_from_account].each do |command|
      script = YAML.load_file(Rails.root.join("config/ssh_commands.yml")).dig("keys", command, "default")
      assert_match(/^runuser -u @{user} -- sh -s --/, script, command)
      assert_no_match(/^(cat|printf)\b.*> ?"\$file"$/, script.split("<<'ELIO'").first, "#{command}: root writes nothing")
    end
  end

  test "adding never writes through a link nor in a file the account does not own, and needs root" do
    without_chown
    root_file = @root.join("root", ".ssh", "authorized_keys")
    before = root_file.read
    %w[mallory eve].each do |user|
      result = authorize(user)
      assert_equal [ :error, "Fichier refusé" ], [ result.status, result.error_title ], user
    end
    assert_equal before, root_file.read, "root's file is untouched"

    refused = authorize("bob", sudo: false)
    assert_equal [ :error, "Root nécessaire" ], [ refused.status, refused.error_title ]
    assert_not_includes @root.join("bob", ".ssh", "authorized_keys").read, "Alice"
  end

  test "a temporary access on another account: replaced with its expiry, then removed from that account" do
    without_chown
    bob = AuthorizedKeysAccount.new(servers(:web), "bob")
    file = @root.join("bob", ".ssh", "authorized_keys")
    assert authorize("bob", expires_at: 1.hour.from_now).added?
    assert authorize("bob", expires_at: 2.hours.from_now, replace: true).added?
    lines = file.read.lines.grep(/Alice/)
    assert_equal 1, lines.size
    assert_match(/\Aexpiry-time="\d{14}Z" /, lines.sole)

    access = TemporaryAccess.create!(server: servers(:web), public_key: public_keys(:alice), unix_user: "bob", key_blob: public_keys(:alice).authorized_key.key,
                                     fingerprint: public_keys(:alice).fingerprint, expires_at: 1.minute.ago)
    assert_equal bob, access.account
    result = Keys::AuthorizedKeyRemoval.call(servers(:web), access.key_blob, account: access.account, transport: fake, known_hosts_file: @known_hosts)
    assert result.removed?
    assert_not_includes file.read, "Alice"
  end
end
