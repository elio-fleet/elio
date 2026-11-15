require "test_helper"

class TemporaryAccessTest < ActiveSupport::TestCase
  include TemporaryAccessHelpers

  test "is valid with a server, an account, a key and an expiry" do
    assert create_temporary_access.persisted?
  end

  test "requires its attributes" do
    access = TemporaryAccess.new
    assert_not access.valid?
    %i[server unix_user key_blob fingerprint expires_at].each { |attribute| assert access.errors.key?(attribute), attribute }
  end

  test "active and expired scopes" do
    valid = create_temporary_access
    expired = create_temporary_access(public_key: public_keys(:alice), expires_at: 1.minute.ago)
    ended = create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 1.minute.ago).tap(&:end!)

    assert_equal [ valid, expired ].sort, TemporaryAccess.active.sort
    assert_equal [ expired ], TemporaryAccess.expired.to_a
    assert_not ended.active?
  end

  test "only one active access per server, account and key" do
    create_temporary_access
    assert_raises(ActiveRecord::RecordNotUnique) { create_temporary_access }

    TemporaryAccess.last.end!
    assert create_temporary_access.persisted?
  end

  test "end! sets ended_at once" do
    access = create_temporary_access
    travel_to(1.minute.from_now) { access.end! }
    ended_at = access.ended_at

    access.end!
    assert_equal ended_at, access.reload.ended_at
  end

  test "account is the server's login account" do
    assert_equal AuthorizedKeysAccount.login(servers(:web)), create_temporary_access.account
  end

  test "keeps the access when the public_key is deleted" do
    access = create_temporary_access
    public_keys(:ci).destroy!

    assert_nil access.reload.public_key
    assert access.active?
  end

  test "durations" do
    assert_equal 10.minutes, TemporaryAccess.duration_for("10")
    assert_equal 7.days, TemporaryAccess.duration_for(10080)
    assert_raises(ArgumentError) { TemporaryAccess.duration_for("5") }
    assert_equal "1 heure", TemporaryAccess.label_for(1.hour)
  end

  test "due for a reminder: active, not reminded yet, ending within the lead time, and long enough" do
    due = create_temporary_access(expires_at: 5.minutes.from_now).tap { |access| access.update_column(:created_at, 2.hours.ago) }
    create_temporary_access(public_key: public_keys(:alice), expires_at: 5.minutes.from_now) # granted for 10 minutes or so: no reminder
    create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 1.hour.from_now).update_column(:created_at, 2.hours.ago)
    create_temporary_access(unix_user: "root", expires_at: 5.minutes.from_now).update_columns(created_at: 2.hours.ago, expiry_reminded_at: 1.minute.ago)

    assert_equal [ due ], TemporaryAccess.due_for_reminder.to_a
  end

  test "remind! records one key_expiring activity" do
    access = create_temporary_access(expires_at: Time.zone.parse("2026-11-15 15:40"))

    2.times { access.remind! }
    TemporaryAccess.find(access.id).remind!

    activity = Activity.of_kind(:key_expiring).sole
    assert_equal [ servers(:web), public_keys(:ci), "deploy", nil ], [ activity.server, activity.public_key, activity.unix_user, activity.user ]
    assert_equal "L'accès temporaire de « CI » sur « Web » se termine à 15 nov. 15:40", activity.summary
    assert access.reload.expiry_reminded_at
  end

  test "an access ended at its term expired, one ended before was removed or replaced" do
    assert create_temporary_access(expires_at: 1.minute.ago).tap(&:end!).expired_at_term?
    assert_not create_temporary_access(public_key: public_keys(:alice), expires_at: 1.hour.from_now).tap(&:end!).expired_at_term?
    assert_not create_temporary_access(unix_user: "root").expired_at_term?
  end
end
