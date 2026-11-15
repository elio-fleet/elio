require "test_helper"

class Keys::RotationCheckTest < ActiveSupport::TestCase
  include LocalShellHelpers

  setup do
    @known_hosts_dir = Dir.mktmpdir
    setup_temp_home
  end

  teardown do
    @home.chmod(0o700)
    @home.join(".ssh").chmod(0o700) if @home.join(".ssh").directory?
    FileUtils.rm_rf(@known_hosts_dir)
    teardown_temp_home
  end

  def check(fake)
    Keys::RotationCheck.call(servers(:web), transport: fake, known_hosts_file: File.join(@known_hosts_dir, "known_hosts"))
  end

  test "ready when the account could create its ~/.ssh, and nothing is written" do
    result = check(FakeSsh.new(handler: local_shell))

    assert result.success?
    assert_equal "Prêt : Elio se connecte et peut ajouter la nouvelle clé.", result.message
    assert_not @home.join(".ssh").exist?
  end

  test "ready when the authorized_keys file is writable" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("ssh-ed25519 AAAA x\n")

    assert check(FakeSsh.new(handler: local_shell)).success?
    assert_equal "ssh-ed25519 AAAA x\n", authorized_keys_file.read
  end

  test "a read-only authorized_keys file would fail" do
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write("")
    authorized_keys_file.chmod(0o400)

    result = check(FakeSsh.new(handler: local_shell))

    assert_equal :read_only, result.status
    assert_equal "Le fichier ~/.ssh/authorized_keys de deploy est en lecture seule : la nouvelle clé ne pourrait pas être ajoutée.", result.message
  end

  test "a read-only ~/.ssh without the file would fail, and so would a read-only home without ~/.ssh" do
    @home.join(".ssh").mkpath
    @home.join(".ssh").chmod(0o500)
    assert_equal "Le dossier ~/.ssh de deploy est en lecture seule : la nouvelle clé ne pourrait pas être ajoutée.", check(FakeSsh.new(handler: local_shell)).message

    @home.join(".ssh").chmod(0o700)
    @home.join(".ssh").rmdir
    @home.chmod(0o500)
    assert_match "Le dossier personnel de deploy", check(FakeSsh.new(handler: local_shell)).message
  end

  test "a refused key and an unreachable server are told apart" do
    refused = check(FakeSsh.new(error: Net::SSH::AuthenticationFailed.new("Authentication failed for user deploy@192.168.1.10")))
    unreachable = check(FakeSsh.new(error: Errno::ECONNREFUSED.new))

    assert_equal [ :key_refused, :unreachable ], [ refused.status, unreachable.status ]
    assert_match "Clé SSH refusée par le serveur", refused.message
    assert_not unreachable.success?
  end
end
