require "test_helper"

class CoolifyKeysTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include CoolifyHelpers
  include KeysReaderHelpers

  test "the keys tab names Coolify's key, not as outside the keyring" do
    sign_in users(:one)
    fake_coolify
    enable_coolify.connections.first.sync!
    keys = AuthorizedKey.parse("#{CoolifyHelpers::COOLIFY_KEY}\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dn stranger")
    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(Keys::AuthorizedKeysReader::Result.new(keys: keys, error_title: nil, error_details: nil))) do
      get server_authorized_keys_path(servers(:web))
    end
    assert_select "li.authorized-key", 2
    assert_select "li.authorized-key:not(.is-orphan) .key-integration", "coolify-master"
    assert_select "li.authorized-key:not(.is-orphan) .source-tag", "Coolify"
    assert_select "li.authorized-key.is-orphan", text: /stranger/
  end
end
