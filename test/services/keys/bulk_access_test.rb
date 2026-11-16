require "test_helper"

class Keys::BulkAccessTest < ActiveSupport::TestCase
  include StubHelpers

  def grant_result(status) = Keys::PublicKeyAuthorization::Result.new(status: status, error_title: (status == :error ? "Connexion impossible" : nil), error_details: (status == :error ? "timeout" : nil))

  setup do
    @reads = []
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call, ->(server, account:) {
      @reads << [ server.name, account.unix_user ]
      Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(public_keys(:alice).content), error_title: nil, error_details: nil)
    })
  end

  test "adds every key on every server's login user, then refreshes each snapshot once" do
    calls = []
    granter = ->(server, public_key, account:, duration:) { calls << [ server.name, public_key.name, account.unix_user, duration ]; grant_result(:added) }

    results = stub_method(Keys::AccessGrant, :call, granter) do
      Keys::BulkAccess.grant([ public_keys(:alice), public_keys(:ci) ], [ servers(:backup), servers(:web) ])
    end

    assert_equal [ [ "Backup", "Alice", "root", nil ], [ "Backup", "CI", "root", nil ], [ "Web", "Alice", "deploy", nil ], [ "Web", "CI", "deploy", nil ] ], calls.sort
    assert_equal [ [ "Backup", "Alice" ], [ "Backup", "CI" ], [ "Web", "Alice" ], [ "Web", "CI" ] ], results.map { |result| [ result.server.name, result.public_key.name ] }
    assert_equal [ "ajoutée" ] * 4, results.map(&:message)
    assert_equal [ [ "Backup", "root" ], [ "Web", "deploy" ] ], @reads.sort
    assert AccountSnapshot.exists?(server: servers(:web), unix_user: "deploy")
  end

  test "a failed grant is an error and does not refresh the snapshot" do
    results = stub_method(Keys::AccessGrant, :call, grant_result(:error)) do
      Keys::BulkAccess.grant([ public_keys(:alice) ], [ servers(:web) ])
    end

    assert results.first.error?
    assert_equal "Connexion impossible — timeout", results.first.message
    assert_empty @reads
  end

  test "revokes the key from every known account, in the servers' order, and forgets it where it is gone" do
    alice = public_keys(:alice)
    [ [ servers(:web), "deploy" ], [ servers(:web), "www-app" ], [ servers(:backup), "root" ] ].each do |server, user|
      AccountSnapshot.record!(server, AuthorizedKeysAccount.new(server, user), AuthorizedKey.parse(alice.content))
    end
    calls = []
    remover = lambda do |server, _blob, account:, **|
      calls << [ server.name, account.unix_user ]
      status = account.unix_user == "www-app" ? :absent : :removed
      Keys::AuthorizedKeyRemoval::Result.new(status: status, error_title: nil, error_details: nil)
    end

    results = stub_method(Keys::AuthorizedKeyRemoval, :call, remover) { Keys::BulkAccess.revoke(alice) }

    assert_equal [ [ "Backup", "root", "retirée" ], [ "Web", "deploy", "retirée" ], [ "Web", "www-app", "déjà absente" ] ],
                 results.map { |result| [ result.server.name, result.unix_user, result.message ] }
    assert_equal [ [ "Backup", "root" ], [ "Web", "deploy" ], [ "Web", "www-app" ] ], calls.sort
    assert_empty AccountSnapshot.with_fingerprint(alice.fingerprint)
    assert_empty Keys::BulkAccess.revoke(alice)
  end

  test "works on several servers at once and keeps the servers' order" do
    running = Concurrent::AtomicFixnum.new
    peak = Concurrent::AtomicFixnum.new
    granter = lambda do |*, **|
      peak.update { |value| [ value, running.increment ].max }
      sleep 0.05
      running.decrement
      grant_result(:added)
    end
    servers = [ servers(:backup), servers(:db), servers(:web) ]

    results = stub_method(Keys::AccessGrant, :call, granter) { Keys::BulkAccess.grant([ public_keys(:alice) ], servers) }

    assert_equal %w[Backup Database Web], results.map { |result| result.server.name }
    assert_operator peak.value, :>, 1
  end
end
