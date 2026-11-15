# Password reset: the request always gets the same answer, so it never tells
# whether an email has an account (Devise's paranoid mode is not used
# globally, it would hide the lockable warnings of the sign-in form). The
# email is sent in the background (User#send_devise_notification): the answer
# takes the same time whether the account exists or not, and an SMTP error
# never reaches the page. Without an email server, asking for a link is
# pointless: the page says so.
class Users::PasswordsController < Devise::PasswordsController
  include Throttled

  before_action :require_mail, only: %i[new create]
  # Per IP, and per email asked for (several IPs cannot flood one inbox).
  throttle only: :create, to: 5, within: 10.minutes, redirect: :new_user_password_path
  throttle only: :create, to: 5, within: 10.minutes, redirect: :new_user_password_path, name: "email",
           by: -> { requested_email }

  def create
    begin
      resource_class.send_reset_password_instructions(resource_params)
    rescue StandardError => e
      Rails.logger.error("[password reset] email not sent: #{e.class}: #{e.message}")
    end
    redirect_to new_session_path(resource_name), notice: t("devise.passwords.send_paranoid_instructions")
  end

  private

  def require_mail
    redirect_to new_session_path(resource_name), alert: t("auth.forgot.unavailable") unless Rails.configuration.x.mail_enabled
  end

  def requested_email
    user = params[:user]
    user.is_a?(ActionController::Parameters) ? user[:email].to_s.strip.downcase : ""
  end
end
