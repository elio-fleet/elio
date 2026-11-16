# Changing the email of one's own account (My account, AccountEmailsController).
# The address is where the password can be reset, so with emails configured the
# new one waits in `unconfirmed_email` until the link sent to it is followed;
# without emails nobody could follow a link, so the change is immediate.
# Both ways ask for the current password.
module EmailChangeable
  extend ActiveSupport::Concern

  CONFIRMATION_VALIDITY = 1.day

  included do
    normalizes :unconfirmed_email, with: ->(email) { email.strip.downcase.presence }
    validates :unconfirmed_email, format: { with: Devise.email_regexp }, allow_nil: true
    validate :unconfirmed_email_must_be_new, if: -> { unconfirmed_email.present? && will_save_change_to_unconfirmed_email? }

    # The link only works for the address it was sent to, and only while the
    # account still has the address it had then.
    generates_token_for :email_change, expires_in: CONFIRMATION_VALIDITY do
      [ email, unconfirmed_email ]
    end
  end

  # Asks for `new_email`, kept unconfirmed when `confirm` (emails configured),
  # else set at once. False with errors when the password or the address is wrong.
  def request_email_change(new_email, current_password:, confirm:)
    errors.clear
    unless valid_password?(current_password)
      errors.add(:current_password, current_password.blank? ? :blank : :invalid)
      return false
    end

    new_email = new_email.to_s.strip.downcase
    if confirm
      self.unconfirmed_email = new_email
      errors.add(:unconfirmed_email, :blank) if unconfirmed_email.nil?
    else
      assign_attributes(email: new_email, unconfirmed_email: nil)
      errors.add(:unconfirmed_email, :unchanged) unless will_save_change_to_email?
    end
    errors.empty? && save
  end

  def email_change_pending? = unconfirmed_email.present?

  # The link of the confirmation email was followed: the new address replaces the old one.
  def confirm_email_change!
    update!(email: unconfirmed_email, unconfirmed_email: nil)
  end

  def cancel_email_change! = update!(unconfirmed_email: nil)

  private

  def unconfirmed_email_must_be_new
    errors.add(:unconfirmed_email, :unchanged) if unconfirmed_email == email
    errors.add(:unconfirmed_email, :taken) if User.where.not(id: id).exists?(email: unconfirmed_email)
  end
end
