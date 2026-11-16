# Security emails to the owner of an account, in their language.
class AccountMailer < ApplicationMailer
  # A backup code opened a session (TwoFactorChallengesController): if it was
  # not them, someone has their password and one of their codes.
  def backup_code_used(user, ip:, at:)
    @user = user
    @ip = ip
    @at = at
    @left = user.backup_codes_left
    @url = account_url
    mail_to_owner(user, "account_mailer.backup_code_used.subject")
  end

  # A sign in from a browser this account never signed in from (KnownDevices):
  # if it was not them, someone has their password.
  def new_device_sign_in(user, ip:, at:, browser:)
    @user = user
    @ip = ip
    @at = at
    @browser = browser.presence
    @url = account_url
    mail_to_owner(user, "account_mailer.new_device_sign_in.subject")
  end

  private

  def mail_to_owner(user, subject_key)
    I18n.with_locale(user.locale || AppSetting.current.default_locale) do
      mail to: user.email, subject: t(subject_key)
    end
  end
end
