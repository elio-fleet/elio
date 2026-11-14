# Password reset: the request always gets the same answer, so it never tells
# whether an email has an account (Devise's paranoid mode is not used
# globally, it would hide the lockable warnings of the sign-in form). An email
# that cannot be sent (SMTP down or refused) is logged and gets the same
# answer too: a different one would tell that the account exists.
class Users::PasswordsController < Devise::PasswordsController
  include Throttled

  throttle only: :create, to: 5, within: 10.minutes, redirect: :new_user_password_path

  def create
    begin
      resource_class.send_reset_password_instructions(resource_params)
    rescue StandardError => e
      Rails.logger.error("[password reset] email not sent: #{e.class}: #{e.message}")
    end
    redirect_to new_session_path(resource_name), notice: t("devise.passwords.send_paranoid_instructions")
  end
end
