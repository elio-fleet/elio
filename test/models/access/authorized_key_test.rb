require "test_helper"

class AuthorizedKeyTest < ActiveSupport::TestCase
  setup do
    @ed25519 = Ssh::KeyGenerator.generate(comment: "alice@laptop").public_key
    @type, @key = @ed25519.split(" ")
  end

  test "parses a key with a comment" do
    key = AuthorizedKey.parse(@ed25519).sole

    assert_equal "ssh-ed25519", key.type
    assert_equal @key, key.key
    assert_equal "alice@laptop", key.name
    assert key.named?
    assert_nil key.options
    assert_equal 1, key.line_number
  end

  test "a key without a comment is unnamed" do
    key = AuthorizedKey.parse("#{@type} #{@key}").sole

    assert_nil key.name
    assert_not key.named?
  end

  test "keeps comments that contain spaces" do
    assert_equal "Alice Martin (laptop)", AuthorizedKey.parse("#{@type} #{@key} Alice Martin (laptop)").sole.name
  end

  test "parses options, including quoted values with spaces" do
    line = %(command="echo hello world",from="10.0.0.1",no-pty #{@type} #{@key} deploy)
    key = AuthorizedKey.parse(line).sole

    assert_equal %(command="echo hello world",from="10.0.0.1",no-pty), key.options
    assert_equal "deploy", key.name
  end

  test "skips blank lines, comments and invalid lines and keeps line numbers" do
    content = <<~KEYS
      # Managed by Elio

      not a key at all
      ssh-ed25519 not-base64!! broken
      #{@type} #{@key} first
      \t
      #{@type} #{@key}
    KEYS

    keys = AuthorizedKey.parse(content)

    assert_equal [ 5, 7 ], keys.map(&:line_number)
    assert_equal [ "first", nil ], keys.map(&:name)
  end

  test "rejects a blob whose embedded type does not match the declared type" do
    assert_empty AuthorizedKey.parse("ssh-rsa #{@key} mismatched")
  end

  test "handles Windows line endings and nil content" do
    assert_equal 2, AuthorizedKey.parse("#{@type} #{@key} a\r\n#{@type} #{@key} b\r\n").size
    assert_equal [], AuthorizedKey.parse(nil)
  end

  test "recognizes RSA and ECDSA keys" do
    rsa = OpenSSL::PKey::RSA.generate(2048)
    ecdsa = OpenSSL::PKey::EC.generate("prime256v1")
    content = [ rsa, ecdsa ].map { |pkey| "#{pkey.ssh_type} #{[ pkey.to_blob ].pack("m0")} #{pkey.class.name}" }.join("\n")

    assert_equal %w[ssh-rsa ecdsa-sha2-nistp256], AuthorizedKey.parse(content).map(&:type)
  end

  test "fingerprint matches the generator's fingerprint" do
    generated = Ssh::KeyGenerator.generate

    assert_equal generated.fingerprint, AuthorizedKey.parse(generated.public_key).sole.fingerprint
  end

  test "matches the app SSH key regardless of the comment" do
    app_key = ssh_keys(:main)
    type, key = app_key.public_key.split(" ")

    assert AuthorizedKey.parse("#{type} #{key} renamed-on-server").sole.matches?(app_key)
    assert_not AuthorizedKey.parse(@ed25519).sole.matches?(app_key)
    assert_not AuthorizedKey.parse(@ed25519).sole.matches?(nil)
  end

  test "matches any key of a list" do
    pending = SshKey.generate_pending!
    key = AuthorizedKey.parse(pending.public_key).sole

    assert key.matches?([ ssh_keys(:main), pending ])
    assert_not key.matches?([ ssh_keys(:main) ])
    assert_not key.matches?([])
  end

  test "flags DSA keys and RSA keys under 3072 bits as weak" do
    line = ->(pkey) { "#{pkey.ssh_type} #{[ pkey.to_blob ].pack("m0")} test" }
    dsa = AuthorizedKey.parse(line.(OpenSSL::PKey::DSA.generate(1024))).sole
    short_rsa = AuthorizedKey.parse(line.(OpenSSL::PKey::RSA.generate(2048))).sole
    long_rsa = AuthorizedKey.parse(line.(OpenSSL::PKey::RSA.generate(3072))).sole

    assert_equal :dsa, dsa.weakness
    assert_equal :rsa_short, short_rsa.weakness
    assert_equal 2048, short_rsa.rsa_bits
    assert_nil long_rsa.weakness
    assert_equal 3072, long_rsa.rsa_bits
    assert_not AuthorizedKey.parse(@ed25519).sole.weak?
    assert_nil AuthorizedKey.parse(@ed25519).sole.rsa_bits
  end
end
