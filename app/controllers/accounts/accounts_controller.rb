# "My account": password and two-factor authentication of the signed-in user.
class AccountsController < ApplicationController
  skip_before_action :require_two_factor_setup

  def show
  end

  def password
    if current_user.update_with_password(params.expect(user: %i[current_password password password_confirmation]))
      bypass_sign_in(current_user)
      redirect_to account_path, notice: t("flash.accounts.password_changed")
    else
      render :show, status: :unprocessable_entity
    end
  end

  # The interface language of the user (blank: the browser's).
  def locale
    current_user.update!(locale: params.expect(user: [ :locale ])[:locale])
    I18n.with_locale(request_locale) do # the new choice
      redirect_to account_path(anchor: "language"), notice: t(".saved")
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to account_path(anchor: "language"), alert: t(".invalid")
  end
end
