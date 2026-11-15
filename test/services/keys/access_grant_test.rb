require "test_helper"

class Keys::AccessGrantTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include StubHelpers
  include TemporaryAccessHelpers

  setup do
    @server = servers(:web)
    @account = AuthorizedKeysAccount.login(@server)
    @calls = []
  end

  # Stubs Keys::PublicKeyAuthorization.call, records its keyword arguments and returns `status`.
  def with_authorization(status)
    authorizer = lambda do |_server, _public_key, **options|
      @calls << options
      Keys::PublicKeyAuthorization::Result.new(status: status, error_title: (status == :error ? "Connexion impossible" : nil), error_details: nil)
    end
    stub_method(Keys::PublicKeyAuthorization, :call, authorizer) { yield }
  end

  test "a permanent grant records nothing" do
    with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account) }

    assert_equal [ { account: @account, expires_at: nil, options: nil, replace: false } ], @calls
    assert_equal 0, TemporaryAccess.count
    assert_no_enqueued_jobs only: ExpireTemporaryAccessJob
  end

  test "a temporary grant writes an expiring line, records the access and schedules its expiry" do
    freeze_time do
      with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account, duration: 10.minutes) }

      assert_equal 10.minutes.from_now, @calls.sole[:expires_at]
      access = TemporaryAccess.sole
      assert_equal [ @server, public_keys(:alice), "deploy", public_keys(:alice).authorized_key.key, public_keys(:alice).fingerprint, 10.minutes.from_now ],
                   [ access.server, access.public_key, access.unix_user, access.key_blob, access.fingerprint, access.expires_at ]
      assert_enqueued_with(job: ExpireTemporaryAccessJob, args: [ access ], at: 10.minutes.from_now)
    end
  end

  test "a temporary grant on a key already authorized permanently keeps it permanent" do
    with_authorization(:already_present) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account, duration: 10.minutes) }

    assert_equal 0, TemporaryAccess.count
    assert_no_enqueued_jobs only: ExpireTemporaryAccessJob
  end

  test "a permanent grant replaces the line of an active temporary access and ends it" do
    access = create_temporary_access

    with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:ci), account: @account) }

    assert @calls.sole[:replace]
    assert_nil @calls.sole[:expires_at]
    assert_not access.reload.active?
    assert_equal 0, TemporaryAccess.active.count
  end

  test "a new temporary grant replaces an active one" do
    old = create_temporary_access

    with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:ci), account: @account, duration: 1.hour) }

    assert @calls.sole[:replace]
    assert_not old.reload.active?
    assert_in_delta 1.hour.from_now, TemporaryAccess.active.sole.expires_at, 5
  end

  test "temporary accesses are per account" do
    root_access = create_temporary_access(unix_user: "root")

    with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:ci), account: @account) }

    assert_not @calls.sole[:replace]
    assert root_access.reload.active?
  end

  test "changes nothing when the authorization fails" do
    access = create_temporary_access

    result = with_authorization(:error) { Keys::AccessGrant.call(@server, public_keys(:ci), account: @account, duration: 10.minutes) }

    assert_not result.success?
    assert access.reload.active?
    assert_equal 1, TemporaryAccess.count
    assert_no_enqueued_jobs only: ExpireTemporaryAccessJob
  end

  test "logs the added key, with its duration" do
    with_authorization(:added) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account, duration: 10.minutes) }

    activity = Activity.of_kind(:key_added).sole
    assert_equal [ @server, public_keys(:alice), "deploy" ], [ activity.server, activity.public_key, activity.unix_user ]
    assert_equal "« Alice » ajoutée sur « Web » pendant 10 minutes", activity.summary
    assert_equal public_keys(:alice).fingerprint, activity.data["fingerprint"]
  end

  test "does not log a key that was already there or a failure" do
    with_authorization(:already_present) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account) }
    with_authorization(:error) { Keys::AccessGrant.call(@server, public_keys(:alice), account: @account) }

    assert_equal 0, Activity.count
  end
end
