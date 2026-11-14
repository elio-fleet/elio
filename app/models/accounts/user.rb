class User < ApplicationRecord
  include Localized
  localized # nil: the browser's language, else the instance's

  # No public sign up: the first admin is created through SetupsController,
  # everyone else through an Invitation.
  # Sessions expire after 30 minutes of inactivity (unless remembered); 10
  # failed attempts (passwords or 2FA codes) lock the account for 15 minutes.
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable,
         :timeoutable, :lockable

  include TwoFactorAuthenticatable

  # The keyring keys this user said are theirs ("my keys").
  has_many :public_keys, -> { order(:name) }, dependent: :nullify, inverse_of: :user


  # What each permission level allows (see Authorization):
  # - view: see everything (dashboard, servers, keys, public_keys, activity)
  # - operate: + manage servers and public_keys, grant / revoke keys, scan
  # - administer: + settings (Elio key, notifications, automations, users)
  PERMISSIONS = {
    view: %w[admin operator viewer],
    operate: %w[admin operator],
    administer: %w[admin]
  }.freeze

  enum :role, { admin: "admin", operator: "operator", viewer: "viewer" }, default: :viewer, validate: true

  validate :must_keep_an_active_admin, on: :update

  scope :active, -> { where(deactivated_at: nil) }

  def can?(permission) = PERMISSIONS.fetch(permission).include?(role)

  def role_label = I18n.t("users.roles.#{role}")

  def self.role_label(role) = I18n.t("users.roles.#{role}")

  def self.role_options = roles.keys.map { |role| [ role_label(role), role ] }

  def deactivated? = deactivated_at.present?

  # Admins must enable 2FA when the setting requires it (see ApplicationController).
  # The settings make the second factor mandatory for this role (admins, and
  # operators who can change the keys on the servers).
  def two_factor_mandatory?(settings = AppSetting.current)
    (admin? && settings.require_admin_two_factor) || (operator? && settings.require_operator_two_factor)
  end

  # Mandatory but not set up yet: the account is sent to set it up first.
  def two_factor_required? = !two_factor_enabled? && two_factor_mandatory?

  def deactivate! = update!(deactivated_at: Time.current)

  def reactivate! = update!(deactivated_at: nil)

  # Devise lockable: logged so a brute force attempt can be noticed / notified.
  def lock_access!(opts = {})
    super(opts.merge(send_instructions: false))
    Activity.record!(:user_locked, user: nil, email: email, attempts: failed_attempts)
  end

  # Counts a failed 2FA code like a failed password; locks after too many.
  def register_failed_two_factor_attempt!
    increment_failed_attempts
    lock_access! if attempts_exceeded? && !access_locked?
  end

  # Devise: a deactivated account cannot sign in, and is signed out on its next request.
  def active_for_authentication? = super && !deactivated?

  def inactive_message = deactivated? ? :deactivated : super

  private

  # The last active admin can neither lose the role nor be deactivated.
  def must_keep_an_active_admin
    was_active_admin = role_was == "admin" && deactivated_at_was.nil?
    still_active_admin = admin? && !deactivated?
    return unless was_active_admin && !still_active_admin
    return if User.active.admin.where.not(id: id).exists?

    errors.add(:base, :last_admin)
  end
end
