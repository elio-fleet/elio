require "test_helper"

class AccountSnapshotTest < ActiveSupport::TestCase
  setup do
    @account = AuthorizedKeysAccount.login(servers(:web))
    @unnamed = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")
  end

  def keys(*lines) = AuthorizedKey.parse(lines.join("\n"))

  test "record! creates then refreshes the snapshot of an account" do
    first = travel_to(1.hour.ago) { AccountSnapshot.record!(servers(:web), @account, keys(public_keys(:alice).content)) }
    second = AccountSnapshot.record!(servers(:web), @account, keys(public_keys(:ci).content, %(no-pty #{@unnamed})))

    assert_equal first, second
    assert_equal 1, AccountSnapshot.count
    assert_equal [ public_keys(:ci).fingerprint, AuthorizedKey.parse(@unnamed).sole.fingerprint ], second.fingerprints
    assert_equal "no-pty", second.keys.last.options
    assert_in_delta Time.current, second.read_at, 2
  end

  test "keeps every part of the lines" do
    line = %(expiry-time="20300101000000Z" #{public_keys(:alice).content})
    snapshot = AccountSnapshot.record!(servers(:web), @account, keys(line))

    assert_equal line, snapshot.reload.content
  end

  test "keys without public_key, named or not, except the Elio key" do
    ci_unnamed = public_keys(:ci).content.split(" ").first(2).join(" ")
    named = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    snapshot = AccountSnapshot.record!(servers(:web), @account, keys(@unnamed, named, ci_unnamed, ssh_keys(:main).public_key.split(" ").first(2).join(" "), public_keys(:alice).content))

    orphans = snapshot.unknown_keys(known_fingerprints: PublicKey.pluck(:fingerprint).to_set, app_key: ssh_keys(:main))

    assert_equal [ nil, "bob@desktop" ], orphans.map(&:name)
  end

  test "with_fingerprint finds the snapshots holding a key" do
    with_alice = AccountSnapshot.record!(servers(:web), @account, keys(public_keys(:alice).content))
    AccountSnapshot.record!(servers(:db), AuthorizedKeysAccount.login(servers(:db)), keys(public_keys(:ci).content))

    assert_equal [ with_alice ], AccountSnapshot.with_fingerprint(public_keys(:alice).fingerprint)
  end

  test "forget! drops a key" do
    snapshot = AccountSnapshot.record!(servers(:web), @account, keys(public_keys(:alice).content, public_keys(:ci).content))

    snapshot.forget!(public_keys(:alice).authorized_key.key)

    assert_equal [ public_keys(:ci).fingerprint ], snapshot.reload.fingerprints
  end

  test "is deleted with its server" do
    AccountSnapshot.record!(servers(:web), @account, [])
    assert_difference("AccountSnapshot.count", -1) { servers(:web).delete }
  end

  test "the first read logs every key without public_key" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key

    AccountSnapshot.record!(servers(:web), @account, keys(@unnamed, bob, public_keys(:alice).content, ssh_keys(:main).public_key))

    detected = Activity.of_kind(:unknown_key_detected).order(:id)
    assert_equal [ nil, "bob@desktop" ], detected.map { |activity| activity.data["key_name"] }
    assert detected.all? { |activity| activity.server == servers(:web) && activity.unix_user == "deploy" }
    assert_equal 0, Activity.of_kind(:key_disappeared).count
  end

  test "later reads log only new keys without public_key and vanished keys" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    eve = Ssh::KeyGenerator.generate(comment: "eve@laptop").public_key
    AccountSnapshot.record!(servers(:web), @account, keys(bob, public_keys(:alice).content))
    Activity.delete_all

    AccountSnapshot.record!(servers(:web), @account, keys(bob, eve))

    assert_equal [ "eve@laptop" ], Activity.of_kind(:unknown_key_detected).map(&:key_name)
    assert_equal [ "alice@laptop" ], Activity.of_kind(:key_disappeared).map(&:key_name)
  end

  test "a key removed through Elio is not reported as vanished" do
    snapshot = AccountSnapshot.record!(servers(:web), @account, keys(public_keys(:alice).content))
    snapshot.forget!(public_keys(:alice).authorized_key.key)

    AccountSnapshot.record!(servers(:web), @account, [])

    assert_equal 0, Activity.of_kind(:key_disappeared).count
  end

  test "the pending Elio key is not reported as a key without public_key" do
    pending = SshKey.generate_pending!

    AccountSnapshot.record!(servers(:web), @account, keys(pending.public_key))

    assert_equal 0, Activity.of_kind(:unknown_key_detected).count
  end

  test "an unknown key on root is a critical activity of its own" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key

    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.new(servers(:web), "root"), keys(bob))

    assert_equal 0, Activity.of_kind(:unknown_key_detected).count
    detected = Activity.of_kind(:unknown_root_key_detected).sole
    assert_equal :critical, detected.severity
    assert_equal [ "root", "bob@desktop" ], [ detected.unix_user, detected.key_name ]
  end

  test "a tolerated key is not reported as unknown" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    ToleratedKey.create!(fingerprint: AuthorizedKey.parse(bob).sole.fingerprint, reason: "Vendor")

    AccountSnapshot.record!(servers(:web), @account, keys(bob))

    assert_equal 0, Activity.of_kind(:unknown_key_detected).count
  end
end
