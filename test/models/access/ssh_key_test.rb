require "test_helper"

class SshKeyTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert ssh_keys(:main).valid?
  end

  test "requires a public key, a private key and a fingerprint" do
    key = SshKey.new
    assert_not key.valid?
    assert key.errors.added?(:public_key, :blank)
    assert key.errors.added?(:private_key, :blank)
    assert key.errors.added?(:fingerprint, :blank)
  end

  test "private key is encrypted at rest" do
    raw = SshKey.connection.select_value("SELECT private_key FROM ssh_keys WHERE id = #{ssh_keys(:main).id}")

    assert_not_includes raw, "OPENSSH PRIVATE KEY"
    assert ssh_keys(:main).private_key.start_with?("-----BEGIN OPENSSH PRIVATE KEY-----")
  end

  test "current returns the most recent key" do
    newer = SshKey.create!(public_key: "ssh-ed25519 AAAA newer", private_key: "private", fingerprint: "SHA256:newer", created_at: 1.minute.from_now)
    assert_equal newer, SshKey.current
  end

  test "current is nil without any key" do
    SshKey.delete_all
    assert_nil SshKey.current
  end

  test "generate! creates a key when there is none" do
    SshKey.delete_all

    key = SshKey.generate!(comment: "elio-test")

    assert_equal 1, SshKey.count
    assert key.persisted?
    assert key.public_key.start_with?("ssh-ed25519 ")
    assert key.public_key.end_with?(" elio-test")
    assert_equal key, SshKey.current
  end

  test "generate! replaces the existing key" do
    old = ssh_keys(:main)

    key = SshKey.generate!

    assert_equal [ key ], SshKey.all.to_a
    assert_not SshKey.exists?(old.id)
    assert_not_equal old.public_key, key.public_key
  end

  test "current is the active key, app_keys the active then the pending one" do
    pending = SshKey.generate_pending!

    assert pending.pending?
    assert_equal ssh_keys(:main), SshKey.current
    assert_equal [ ssh_keys(:main), pending ], SshKey.app_keys
  end

  test "generate! replaces every key, pending included" do
    SshKey.generate_pending!

    key = SshKey.generate!

    assert_equal [ key ], SshKey.all.to_a
    assert key.active?
  end

  test "blob is the base64 part of the public key" do
    assert_equal ssh_keys(:main).public_key.split(" ")[1], ssh_keys(:main).blob
  end

  test "a rotation is due once the key is a year old" do
    key = ssh_keys(:main)
    key.update_column(:created_at, 11.months.ago)
    assert_not key.rotation_due?

    key.update_column(:created_at, 13.months.ago)
    assert key.rotation_due?
  end
end
