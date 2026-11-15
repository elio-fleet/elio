require "test_helper"

class PublicKeyTest < ActiveSupport::TestCase
  setup do
    @key = Ssh::KeyGenerator.generate(comment: "bob@desktop")
  end

  def build_public_key(**attributes)
    PublicKey.new({ name: "Bob", content: @key.public_key }.merge(attributes))
  end

  test "fixtures are valid" do
    assert public_keys(:alice).valid?
    assert public_keys(:ci).valid?
  end

  test "is valid with a name and a public key" do
    assert build_public_key.valid?
  end

  test "requires a name and a public key" do
    public_key = PublicKey.new
    assert_not public_key.valid?
    assert public_key.errors.added?(:name, :blank)
    assert public_key.errors.added?(:content, :blank)
  end

  test "name is unique, case insensitive" do
    public_key = build_public_key(name: "alice")
    assert_not public_key.valid?
    assert public_key.errors.of_kind?(:name, :taken)
  end

  test "squishes the name and strips the public key" do
    public_key = build_public_key(name: "  Bob   Martin ", content: "\n  #{@key.public_key}  \n")
    assert_equal "Bob Martin", public_key.name
    assert_equal @key.public_key, public_key.content
  end

  test "computes the fingerprint from the public key" do
    public_key = build_public_key
    public_key.validate
    assert_equal @key.fingerprint, public_key.fingerprint
  end

  test "accepts a public key without a comment" do
    assert build_public_key(content: @key.public_key.split(" ").first(2).join(" ")).valid?
  end

  test "accepts RSA and ECDSA public keys" do
    [ OpenSSL::PKey::RSA.generate(2048), OpenSSL::PKey::EC.generate("prime256v1") ].each do |pkey|
      public_key = build_public_key(content: "#{pkey.ssh_type} #{[ pkey.to_blob ].pack("m0")} key")
      assert public_key.valid?, "#{pkey.ssh_type} should be valid: #{public_key.errors.full_messages}"
    end
  end

  test "rejects garbage" do
    public_key = build_public_key(content: "not a key")
    assert_not public_key.valid?
    assert public_key.errors.added?(:content, :invalid)
    assert_nil public_key.fingerprint
  end

  test "rejects several keys" do
    other = Ssh::KeyGenerator.generate.public_key
    public_key = build_public_key(content: "#{@key.public_key}\n#{other}")
    assert_not public_key.valid?
    assert public_key.errors.added?(:content, :invalid)
  end

  test "rejects a key with authorized_keys options" do
    public_key = build_public_key(content: %(no-pty #{@key.public_key}))
    assert_not public_key.valid?
    assert public_key.errors.added?(:content, :invalid)
  end

  test "rejects a private key with an explicit message" do
    public_key = build_public_key(content: @key.private_key)
    assert_not public_key.valid?
    assert public_key.errors.added?(:content, :private_key)
    assert_match "ressemble à une clé privée", public_key.errors.full_messages.to_sentence
  end

  test "rejects a key already used by another public_key, whatever its comment" do
    type, blob = public_keys(:alice).content.split(" ")
    public_key = build_public_key(content: "#{type} #{blob} renamed")
    assert_not public_key.valid?
    assert public_key.errors.of_kind?(:fingerprint, :taken)
  end

  test "rejects the Elio key" do
    public_key = build_public_key(content: ssh_keys(:main).public_key)
    assert_not public_key.valid?
    assert public_key.errors.added?(:content, :app_key)
  end

  test "authorized_key returns the parsed key" do
    key = public_keys(:alice).authorized_key
    assert_equal "alice@laptop", key.name
    assert_equal public_keys(:alice).fingerprint, key.fingerprint
  end

  test "authorized_key is nil for an invalid key" do
    assert_nil build_public_key(content: "nope").authorized_key
  end

  test "the database enforces unique names and fingerprints" do
    duplicate = public_keys(:alice).dup
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "is a person's key by default, or a server's" do
    assert_equal "person", build_public_key.kind
    assert_equal "Personne", build_public_key.kind_label
    assert build_public_key(kind: "server").server?
    assert_equal "Serveur", public_keys(:ci).kind_label
  end

  test "rejects an unknown kind" do
    public_key = build_public_key(kind: "robot")

    assert_not public_key.valid?
    assert public_key.errors.added?(:kind, :inclusion, value: "robot")
  end

  test "the description is optional and trimmed" do
    assert_nil build_public_key(description: "   ").tap(&:validate).description
    assert_equal "Portable", build_public_key(description: "  Portable ").tap(&:validate).description
  end

  test "of_kind filters by kind" do
    assert_equal [ public_keys(:ci) ], PublicKey.of_kind("server").to_a
    assert_equal [ public_keys(:alice) ], PublicKey.of_kind("person").to_a
  end

  test "a weak key is flagged, through its parsed key" do
    rsa = OpenSSL::PKey::RSA.generate(2048)
    weak = build_public_key(content: "ssh-rsa #{[ rsa.to_blob ].pack("m0")} old@laptop")

    assert_equal [ :rsa_short, 2048 ], [ weak.weakness, weak.rsa_bits ]
    assert_not build_public_key.weak?
    assert_nil build_public_key(content: "garbage").weakness
  end

  test "expired and expiring soon follow the expiry date" do
    assert_not build_public_key.expired?
    assert_not build_public_key.expiring_soon?
    assert build_public_key(expires_on: Date.current).expired?
    assert build_public_key(expires_on: 10.days.from_now.to_date).expiring_soon?
    assert_not build_public_key(expires_on: 30.days.from_now.to_date).expiring_soon?
  end

  test "due_for_expiry_reminder: a date within 14 days or past, not reminded yet" do
    public_keys(:alice).update!(expires_on: 13.days.from_now.to_date)
    public_keys(:ci).update!(expires_on: 20.days.from_now.to_date)

    assert_equal [ public_keys(:alice) ], PublicKey.due_for_expiry_reminder.to_a

    public_keys(:alice).remind_expiry!
    assert_empty PublicKey.due_for_expiry_reminder
  end

  test "remind_expiry! records one public_key_expiring activity, again after a new date" do
    public_key = public_keys(:alice)
    public_key.update!(expires_on: Date.new(2026, 12, 1))

    2.times { public_key.reload.remind_expiry! }

    activity = Activity.of_kind(:public_key_expiring).sole
    assert_equal [ public_key, nil, "2026-12-01" ], [ activity.public_key, activity.user, activity.data["expires_on"] ]
    assert_equal :warning, activity.severity

    public_key.reload.update!(expires_on: Date.new(2027, 12, 1))
    assert_nil public_key.expiry_reminded_at
    public_key.remind_expiry!
    assert_equal 2, Activity.of_kind(:public_key_expiring).count
  end

  test "the reminder summary says whether the key has expired" do
    travel_to Time.zone.local(2026, 11, 20, 10) do
      public_key = public_keys(:alice)
      public_key.update!(expires_on: Date.new(2026, 12, 1))
      public_key.remind_expiry!
      assert_equal "La clé « Alice » du trousseau expire le 1 décembre 2026, à renouveler", Activity.of_kind(:public_key_expiring).reorder(:id).last.summary

      public_key.update!(expires_on: Date.new(2026, 11, 1))
      public_key.remind_expiry!
      assert_equal "La clé « Alice » du trousseau a expiré le 1 novembre 2026, à renouveler", Activity.of_kind(:public_key_expiring).reorder(:id).last.summary
    end
  end
end
