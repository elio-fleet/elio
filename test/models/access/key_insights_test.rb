require "test_helper"

class KeyInsightsTest < ActiveSupport::TestCase
  def unnamed_key = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")

  def record(server, *lines)
    AccountSnapshot.record!(server, AuthorizedKeysAccount.login(server), AuthorizedKey.parse(lines.join("\n")))
  end

  test "nothing scanned yet" do
    insights = KeyInsights.new

    assert_not insights.scanned?
    assert_equal 0, insights.orphan_count
    assert_equal({}, insights.orphans_by_server_id)
  end

  test "lists the keys without public_key per server" do
    unnamed = unnamed_key
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    record(servers(:web), unnamed, bob, public_keys(:alice).content, ssh_keys(:main).public_key)
    travel_to(1.day.ago) { record(servers(:db), public_keys(:ci).content) }

    insights = KeyInsights.new

    assert insights.scanned?
    assert_equal [ nil, "bob@desktop" ], insights.orphans_by_server_id[servers(:web).id].map(&:name)
    assert_equal [], insights.orphans_by_server_id[servers(:db).id]
    assert_equal 2, insights.orphan_count
  end

  test "a tolerated key is no longer outside the keyring and is listed with where it is" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    record(servers(:web), bob)
    ToleratedKey.create!(fingerprint: AuthorizedKey.parse(bob).sole.fingerprint, name: "bob@desktop", reason: "Vendor")
    ToleratedKey.create!(fingerprint: "SHA256:gone", reason: "Old")

    insights = KeyInsights.new

    assert_equal 0, insights.orphan_count
    assert_empty insights.outside_keys
    assert_equal [ [ "Old", [] ], [ "Vendor", [ [ servers(:web), "deploy" ] ] ] ].sort_by(&:first),
                 insights.tolerated_keys.map { |entry| [ entry.record.reason, entry.places ] }.sort_by(&:first)
  end

  test "an outside key on root, and when each key was first reported" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    fingerprint = AuthorizedKey.parse(bob).sole.fingerprint
    travel_to(2.days.ago) { record(servers(:web), bob) }
    AccountSnapshot.record!(servers(:db), AuthorizedKeysAccount.new(servers(:db), "root"), AuthorizedKey.parse(bob))

    entry = KeyInsights.new.outside_keys.sole
    assert entry.root?

    first_seen = KeyInsights.first_seen([ fingerprint, "SHA256:none" ])
    assert_equal [ fingerprint ], first_seen.keys
    assert_in_delta 2.days.ago, first_seen[fingerprint], 5
    assert_equal({}, KeyInsights.first_seen([]))
  end
end
