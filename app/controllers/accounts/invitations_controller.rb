# Accepting an invitation (public page reached through the invitation link).
class InvitationsController < ApplicationController
  layout "auth"

  skip_before_action :authenticate_user!, :authorize_view!
  before_action :redirect_signed_in_user
  rate_limit to: 10, within: 3.minutes, only: :accept, store: Throttled::STORE,
             with: -> { redirect_to new_user_session_path, alert: t("throttled.too_many"), status: :see_other }
  before_action :set_invitation

  def show
    @user = User.new(email: @invitation.email)
  end

  def accept
    passwords = params.expect(user: %i[password password_confirmation])
    @user = @invitation.accept!(password: passwords[:password], password_confirmation: passwords[:password_confirmation])
    Activity.record!(:invitation_accepted, user: @user, email: @user.email, role: @user.role)

    sign_in(@user)
    redirect_to root_path, notice: t("flash.invitations.welcome")
  rescue ActiveRecord::RecordInvalid => e
    @user = e.record.is_a?(User) ? e.record : User.new(email: @invitation.email)
    render :show, status: :unprocessable_entity
  end

  private

  def redirect_signed_in_user
    redirect_to root_path, alert: t("flash.invitations.signed_in") if user_signed_in?
  end

  def set_invitation
    @invitation = Invitation.find_pending_by_token(params[:token])
    render :invalid, status: :not_found unless @invitation
  end

  # The page of an invitation speaks the language chosen for it (that of its
  # email and of the account it creates), not the browser's.
  # (Read here: the locale is chosen around every callback, before set_invitation.)
  def request_locale = Elio::Locales.find(Invitation.find_pending_by_token(params[:token])&.locale) || super
end
