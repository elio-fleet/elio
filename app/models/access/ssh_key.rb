# The key pair the app uses to connect to every server. Its public key must be
# added to the servers' authorized_keys. There is one active key, plus a
# pending one while a KeyRotation replaces it: both are Elio's keys then
# (connections try both, neither counts as an unknown key nor can be removed).
class SshKey < ApplicationRecord
  encrypts :private_key

  enum :state, { active: "active", pending: "pending" }, default: :active, validate: true

  validates :public_key, :private_key, :fingerprint, presence: true

  def self.current
    active.order(:created_at).last
  end

  # Active then pending key: the keys Elio connects with and protects.
  def self.app_keys
    where(state: %w[active pending]).in_order_of(:state, %w[active pending]).to_a
  end

  # Replaces every key with a freshly generated active one (cuts the access to
  # servers until its public key is installed; see KeyRotation for no downtime).
  def self.generate!(comment: "elio")
    transaction do
      delete_all
      build_generated(comment: comment).tap(&:save!)
    end
  end

  def self.generate_pending!(comment: "elio")
    build_generated(comment: comment, state: :pending).tap(&:save!)
  end

  def self.build_generated(comment:, state: :active)
    key = Ssh::KeyGenerator.generate(comment: comment)
    new(public_key: key.public_key, private_key: key.private_key, fingerprint: key.fingerprint, state: state)
  end
  private_class_method :build_generated

  # Past this age, the settings remind to rotate the key (a leak nobody noticed
  # stays usable as long as the key does).
  ROTATION_REMINDER_AGE = 1.year

  def blob = public_key.split(" ")[1]

  def rotation_due? = created_at < ROTATION_REMINDER_AGE.ago
end
