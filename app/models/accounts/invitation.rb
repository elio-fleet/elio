# Invitation to join Elio with a role, accepted through a single-use link
# (/invitations/:token) valid for VALIDITY. The token is encrypted
# (deterministic, so it can be looked up) and kept so admins can copy the
# link again while the invitation is pending.
class Invitation < ApplicationRecord
  include Localized
  localized # the invitation email and the new account's language

  VALIDITY = 7.days
  # Expired invitations stay listed (to be resent in one click) that long,
  # then expired and revoked ones are purged (PurgeInvitationsJob).
  KEPT = 30.days
  # Addresses accepted at once by the invitation form.
  MAX_AT_ONCE = 20

  belongs_to :invited_by, class_name: "User"
  belongs_to :user, optional: true

  encrypts :token, deterministic: true

  normalizes :email, with: ->(value) { value.strip.downcase }

  enum :role, User.roles, default: :viewer, validate: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validate :email_must_be_free, on: :create

  before_validation(on: :create) do
    self.token ||= SecureRandom.urlsafe_base64(32)
    self.expires_at ||= VALIDITY.from_now
  end

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where(expires_at: Time.current..) }
  # Expired without being accepted or revoked, recently enough to be resent.
  scope :expired_unanswered, -> { where(accepted_at: nil, revoked_at: nil).where(expires_at: KEPT.ago...Time.current) }
  # Accepted invitations are kept: they tell who invited each account.
  scope :purgeable, -> { where(accepted_at: nil).where("revoked_at < :limit OR expires_at < :limit", limit: KEPT.ago) }

  # Splits what was typed in the form ("a@x.org, b@x.org" or one per line)
  # into distinct addresses, in the order typed.
  def self.split_emails(text)
    text.to_s.split(/[\s,;]+/).map { |email| email.strip.downcase }.compact_blank.uniq
  end

  def self.find_pending_by_token(token)
    invitation = find_by(token: token.to_s) if token.present?
    invitation if invitation&.pending?
  end

  def pending? = accepted_at.nil? && revoked_at.nil? && !expired?

  def expired? = expires_at <= Time.current

  def status
    if accepted_at then :accepted
    elsif revoked_at then :revoked
    elsif expired? then :expired
    else :pending
    end
  end

  def role_label = User.role_label(role)

  # Creates the account with the invitation's email and role.
  def accept!(password:, password_confirmation:)
    raise ActiveRecord::RecordInvalid, self unless pending?

    transaction do
      account = User.create!(email: email, role: role, locale: locale, password: password, password_confirmation: password_confirmation)
      update!(user: account, accepted_at: Time.current)
      account
    end
  end

  # Gives an expired invitation a new validity period and a new link (the old
  # one may have been forwarded meanwhile: it stays invalid), sent again by
  # `by`. Refused if the person has joined or been invited since.
  def renew!(by:)
    raise ActiveRecord::RecordInvalid, self unless status == :expired

    email_must_be_free
    raise ActiveRecord::RecordInvalid, self if errors.any?

    update!(invited_by: by, token: SecureRandom.urlsafe_base64(32), expires_at: VALIDITY.from_now)
  end

  def revoke!
    update!(revoked_at: Time.current) if pending?
  end

  private

  def email_must_be_free
    if User.exists?(email: email)
      errors.add(:email, :taken_by_user)
    elsif Invitation.pending.exists?(email: email)
      errors.add(:email, :already_invited)
    end
  end
end
