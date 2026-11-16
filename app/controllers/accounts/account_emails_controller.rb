# The email of the signed-in user, in My account (see EmailChangeable). With
# emails configured, the new address receives a link to confirm it and the
# current one a warning; the address changes when the link is followed, signed
# in as the same user. Without emails, it changes at once.
class AccountEmailsController < ApplicationController
  skip_before_action :require_two_factor_setup, :redirect_to_password_change

  def update
    attributes = params.expect(user: %i[email current_password])
    confirm = Rails.configuration.x.mail_enabled
    from = current_user.email
    unless current_user.request_email_change(attributes[:email], current_password: attributes[:current_password], confirm: confirm)
      return redirect_to account_path(anchor: "email"), alert: current_user.errors.full_messages.to_sentence, status: :see_other
    end

    if confirm
      AccountMailer.email_change_confirmation(current_user).deliver_later
      AccountMailer.email_change_requested(current_user).deliver_later
      redirect_to account_path(anchor: "email"), notice: t(".sent", email: current_user.unconfirmed_email), status: :see_other
    else
      Activity.record!(:user_email_changed, from: from, email: current_user.email)
      redirect_to account_path(anchor: "email"), notice: t(".changed"), status: :see_other
    end
  end

  # The link of the confirmation email.
  def confirm
    user = User.find_by_token_for(:email_change, params[:token].to_s)
    return redirect_to account_path(anchor: "email"), alert: t(".invalid") unless user == current_user && user.email_change_pending?

    from = user.email
    user.confirm_email_change!
    Activity.record!(:user_email_changed, from: from, email: user.email)
    redirect_to account_path(anchor: "email"), notice: t(".confirmed", email: user.email)
  rescue ActiveRecord::RecordInvalid
    redirect_to account_path(anchor: "email"), alert: user.errors.full_messages.to_sentence
  end

  def destroy
    current_user.cancel_email_change!
    redirect_to account_path(anchor: "email"), notice: t(".cancelled"), status: :see_other
  end
end
