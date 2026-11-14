require "test_helper"

class EncryptedRecordsTest < ActiveSupport::TestCase
  include TwoFactorHelpers

  TEST_KEY = ActiveRecord::Encryption.config.primary_key

  def provider(*keys) = ActiveRecord::Encryption::DerivedSecretKeyProvider.new(keys.many? ? keys : keys.first)

  def with_keys(*keys, &block) = ActiveRecord::Encryption.with_encryption_context(key_provider: provider(*keys), &block)

  test "every model that holds an encrypted secret is listed" do
    assert_equal %w[AppSetting Integration IntegrationConnection Invitation NotificationChannel SshKey User], EncryptedRecords.models.map(&:name)
  end

  test "after a rotation, re-encrypting moves every secret to the new key, the former one can go" do
    user = users(:operator)
    with_keys("former-primary-key-0123456789abc") { user.update!(otp_secret: "JBSWY3DPEHPK3PXP") }
    with_keys(TEST_KEY, "former-primary-key-0123456789abc", "new-primary-key-0123456789abcdef") do
      assert_equal "JBSWY3DPEHPK3PXP", User.find(user.id).otp_secret
      counts = EncryptedRecords.reencrypt!
      assert_equal User.count, counts["User"]
      assert_equal SshKey.count, counts["SshKey"]
    end

    with_keys("new-primary-key-0123456789abcdef") do
      assert_equal "JBSWY3DPEHPK3PXP", User.find(user.id).otp_secret
      assert SshKey.first.private_key.start_with?("-----BEGIN")
    end
    with_keys("former-primary-key-0123456789abc") do
      assert_raises(ActiveRecord::Encryption::Errors::Decryption) { User.find(user.id).otp_secret }
    end
  end
end
