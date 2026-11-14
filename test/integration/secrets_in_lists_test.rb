require "test_helper"

# The lists of records that hold secrets (users and their 2FA secret,
# notification channels and their webhook, extensions and their API keys,
# Elio's SSH key, registry credentials) never decrypt them: a secret is read
# only when it is used, never to draw a page. (Settings → Notifications reads
# each webhook on purpose: it shows its host, the rest masked.)
class SecretsInListsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include TwoFactorHelpers
  include SlackHelpers

  # Counts the decryptions, without changing them.
  class CountingEncryptor < ActiveRecord::Encryption::Encryptor
    attr_reader :decrypted

    def decrypt(...)
      @decrypted = (@decrypted || 0) + 1
      super
    end
  end

  setup do
    enable_two_factor(users(:operator))
    create_channel(signing_secret: "s3cret")
    Integration.create!(kind: "uptime_kuma", enabled: true, settings: { "url" => "https://kuma.test" }, secrets: { "api_key" => "k" })
    AppSetting.current.update!(docker_registry_credentials: "ghcr.io elio ghp_secret")
    sign_in users(:one)
  end

  test "the counter sees a decryption (the tests below cannot pass by mistake)" do
    encryptor = CountingEncryptor.new
    ActiveRecord::Encryption.with_encryption_context(encryptor: encryptor) { NotificationChannel.last.webhook_url }
    assert_equal 1, encryptor.decrypted
  end

  {
    "users" => -> { settings_users_path },
    "extensions" => -> { settings_integrations_path },
    "servers" => -> { servers_path },
    "SSH keys" => -> { public_keys_path }
  }.each do |name, path|
    test "the #{name} list decrypts no secret" do
      encryptor = CountingEncryptor.new
      ActiveRecord::Encryption.with_encryption_context(encryptor: encryptor) { get instance_exec(&path) }
      assert_response :success
      assert_nil encryptor.decrypted, "#{encryptor.decrypted} secret(s) decrypted to draw the #{name} list"
    end
  end
end
