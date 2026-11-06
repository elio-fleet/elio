require "test_helper"

class Keys::ServerScanTest < ActiveSupport::TestCase
  include StubHelpers

  setup do
    @server = servers(:web)
  end

  def read_result(keys: "", error_title: nil, reason: nil)
    Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(keys), error_title: error_title, error_details: nil, reason: reason)
  end

  test "reads the login account and records its snapshot" do
    accounts = []
    reader = ->(_server, account:, **) { accounts << account.unix_user; read_result(keys: public_keys(:alice).content) }

    result = stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) { Keys::ServerScan.call(@server) }

    assert result.success?
    assert_equal %w[deploy], accounts
    assert_equal [ public_keys(:alice).fingerprint ], AccountSnapshot.find_by!(server: @server, unix_user: "deploy").fingerprints
    assert @server.reload.ssh_ok
  end

  test "records a refused key and no snapshot" do
    refused = read_result(error_title: "Clé SSH refusée par le serveur", reason: :key_refused)

    result = stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(refused)) { Keys::ServerScan.call(@server) }

    assert_not result.success?
    assert_equal "Clé SSH refusée par le serveur", result.error_title
    assert_equal false, @server.reload.ssh_ok
    assert_equal 0, AccountSnapshot.count
  end

  test "an unreachable server keeps its SSH status" do
    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(read_result(error_title: "Connexion impossible"))) { Keys::ServerScan.call(@server) }

    assert_nil @server.reload.ssh_ok
  end
end
