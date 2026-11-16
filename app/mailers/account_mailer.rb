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
    I18n.with_locale(user.locale || AppSetting.current.default_locale) do
      mail to: user.email, subject: t("account_mailer.backup_code_used.subject")
    end
  end

  # A new address was asked in My account: the link that makes it the account's.
  def email_change_confirmation(user)
    @user = user
    @url = confirm_account_email_url(token: user.generate_token_for(:email_change))
    @hours = (EmailChangeable::CONFIRMATION_VALIDITY / 1.hour).round
    I18n.with_locale(user.locale || AppSetting.current.default_locale) do
      mail to: user.unconfirmed_email, subject: t("account_mailer.email_change_confirmation.subject")
    end
  end

  # The same request, told to the current address: if it was not them, someone
  # is signed in to their account.
  def email_change_requested(user)
    @user = user
    @url = account_url
    I18n.with_locale(user.locale || AppSetting.current.default_locale) do
      mail to: user.email, subject: t("account_mailer.email_change_requested.subject")
    end
  end
end
