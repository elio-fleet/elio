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
end
