require "test_helper"

class KeyPresenceTest < ActiveSupport::TestCase
  def record(server, unix_user, *lines)
    AccountSnapshot.record!(server, AuthorizedKeysAccount.new(server, unix_user), AuthorizedKey.parse(lines.join("\n")))
  end

  test "nothing scanned yet: every server is unknown" do
    presence = KeyPresence.new

    assert presence.any?
    assert_equal({ unknown: Server.order(:name).to_a }, presence.by_state)
  end

  test "reads the key from the snapshot of the account Elio logs in with" do
    web, db, backup = servers(:web, :db, :backup)
    record(web, "deploy", %(from="203.0.113.10" #{ssh_keys(:main).public_key}))
    record(db, "admin", public_keys(:alice).content)
    record(db, "postgres", ssh_keys(:main).public_key) # another account than Elio's
    record(backup, "root", public_keys(:alice).content)
    backup.update_columns(ssh_ok: true)

    presence = KeyPresence.new

    assert_equal :installed, presence.state(web)
    assert_equal :missing, presence.state(db)
    assert_equal :missing, presence.state(backup)
    assert_equal [ :missing, :installed ], presence.by_state.keys
    assert_equal 2, presence.count(:missing)
    assert_equal 0, presence.count(:failing)
  end

  test "the pending key of a rotation counts as Elio's key" do
    pending = SshKey.generate_pending!
    record(servers(:web), "deploy", pending.public_key)

    assert_equal :installed, KeyPresence.new.state(servers(:web))
  end

  test "a failed SSH login wins over an older scan, unreachable servers apart" do
    web, db = servers(:web, :db)
    record(web, "deploy", ssh_keys(:main).public_key)
    record(db, "admin", ssh_keys(:main).public_key)
    web.update_columns(ssh_ok: false, reachable: true)
    db.update_columns(ssh_ok: false, reachable: false)

    presence = KeyPresence.new

    assert_equal :failing, presence.state(web)
    assert_equal :unreachable, presence.state(db)
    assert_equal %i[failing unreachable unknown], presence.by_state.keys
  end

  test "no server" do
    assert_not KeyPresence.new(servers: []).any?
  end

  test "labels count the servers" do
    assert_equal "Clé installée sur 2 serveurs", KeyPresence.state_label(:installed, 2)
    I18n.with_locale(:en) { assert_equal "1 unreachable server", KeyPresence.state_label(:unreachable, 1) }
  end
end
