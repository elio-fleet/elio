require "test_helper"

class ElioSecretsTest < ActiveSupport::TestCase
  test "reads the encryption keys that are set in the environment" do
    env = { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "p", "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => " ", "OTHER" => "x" }
    assert_equal({ primary_key: "p" }, Elio::Secrets.encryption_keys(env))
    assert_empty Elio::Secrets.encryption_keys({})
  end

  test "during a rotation, the former primary keys are still read and the current one encrypts (last)" do
    env = { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "new", "ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS" => " old1, old2,,new " }
    assert_equal({ primary_key: %w[old1 old2 new] }, Elio::Secrets.encryption_keys(env))
    assert_equal({}, Elio::Secrets.encryption_keys("ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS" => "old"))
  end

  test "bin/elio-keys prints a fresh set of variables, different each time" do
    output = `#{RbConfig.ruby} #{Rails.root.join("bin/elio-keys")}`
    variables = output.lines.to_h { |line| line.chomp.split("=", 2) }
    assert_equal %w[SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT], variables.keys
    assert_equal 128, variables["SECRET_KEY_BASE"].size
    assert_equal [ 32 ] * 3, variables.except("SECRET_KEY_BASE").values.map(&:size)
    assert_not_equal output, `#{RbConfig.ruby} #{Rails.root.join("bin/elio-keys")}`
  end

  test "the tests do not depend on the credentials of an installation" do
    assert_equal "test-primary-key-0123456789abcdef", ActiveRecord::Encryption.config.primary_key
  end

  test "the version follows semantic versioning and is shown in the sidebar" do
    assert_match(/\A\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?\z/, Elio::VERSION)
  end
end
