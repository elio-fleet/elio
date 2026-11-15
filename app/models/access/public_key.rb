# A key of the keyring ("Trousseau"): the SSH public key of a team member or
# of a server (e.g. a CI runner, a backup host), that can be added to or
# removed from the servers. `content` is one OpenSSH public key line.
class PublicKey < ApplicationRecord
  KINDS = %w[person server].freeze

  # The public_key_expiring activity is recorded this long before the expiry
  # date (or as soon as a past date is set), once per date.
  EXPIRY_REMINDER_LEAD = 14.days

  # Its owner ("my key", see AccountKeysController): a person's key, one
  # owner at most.
  belongs_to :user, optional: true

  normalizes :name, with: ->(value) { value.squish }
  normalizes :content, with: ->(value) { value.strip }
  normalizes :description, with: ->(value) { value.strip.presence }

  before_validation :set_fingerprint
  before_save :forget_expiry_reminder, if: :will_save_change_to_expires_on?

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :content, presence: true
  validate :content_must_be_a_single_public_key
  validate :content_must_not_be_the_app_key
  validate :owner_only_for_a_person
  validates :fingerprint, uniqueness: true, if: :authorized_key

  scope :of_kind, ->(kind) { where(kind: kind) }
  scope :unowned, -> { where(user_id: nil) }
  scope :due_for_expiry_reminder, -> { where(expiry_reminded_at: nil, expires_on: ..EXPIRY_REMINDER_LEAD.from_now.to_date) }

  delegate :weakness, :weak?, :rsa_bits, to: :authorized_key, allow_nil: true

  def kind_label = self.class.kind_label(kind)

  def self.kind_label(kind) = I18n.t("public_key.kinds.#{kind}")

  def server? = kind == "server"

  # The parsed key, or nil when content is not exactly one valid public key.
  def authorized_key
    keys = AuthorizedKey.parse(content)
    keys.sole if keys.one? && keys.first.options.nil? && !content.include?("\n")
  end

  # Past its expiry date (the key should have been rotated), or close to it.
  def expired? = expires_on.present? && expires_on <= Date.current

  def expiring_soon? = expires_on.present? && !expired? && expires_on <= EXPIRY_REMINDER_LEAD.from_now.to_date

  # Records the public_key_expiring activity, once (several workers may run the reminder at once).
  def remind_expiry!
    return unless self.class.where(id: id, expiry_reminded_at: nil).update_all(expiry_reminded_at: Time.current) == 1

    Activity.record!(:public_key_expiring, public_key: self, user: nil, fingerprint: fingerprint, expires_on: expires_on.iso8601)
  end

  private

  # A new date gets its own reminder. Marked as changed: remind_expiry! sets
  # the column in the database only, the loaded value can still be nil.
  def forget_expiry_reminder
    expiry_reminded_at_will_change!
    self.expiry_reminded_at = nil
  end

  def set_fingerprint
    self.fingerprint = authorized_key&.fingerprint
  end

  def content_must_be_a_single_public_key
    return if content.blank? || authorized_key

    if content.include?("PRIVATE KEY")
      errors.add(:content, :private_key)
    else
      errors.add(:content, :invalid)
    end
  end

  def owner_only_for_a_person
    errors.add(:user, :server_key) if user_id && server?
  end

  def content_must_not_be_the_app_key
    errors.add(:content, :app_key) if authorized_key&.matches?(SshKey.app_keys)
  end
end
