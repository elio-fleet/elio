module Settings
  class UsersController < ApplicationController
    PER_PAGE = 50

    require_permission :administer

    before_action :set_user, only: %i[update deactivate reactivate reset_two_factor unlock]

    def index
      @pager = paginate(User.order(:email), per_page: PER_PAGE)
      @users = @pager.records
      @invitations = Invitation.pending.includes(:invited_by).order(created_at: :desc)
      @expired_invitations = Invitation.expired_unanswered.includes(:invited_by).order(expires_at: :desc)
      @invitation = Invitation.new
      @setting = AppSetting.current
    end

    # Role.
    def update
      previous_role = @user.role

      if @user.update(params.expect(user: %i[role]))
        if @user.saved_change_to_role?
          Activity.record!(:user_role_changed, email: @user.email, from_role: previous_role, to_role: @user.role)
        end
        redirect_to settings_users_path, notice: t("flash.users.updated", email: @user.email)
      else
        redirect_to settings_users_path, alert: t("flash.users.update_failed", email: @user.email, errors: @user.errors.full_messages.to_sentence)
      end
    end

    def deactivate
      return redirect_to(settings_users_path, alert: t("flash.users.cannot_deactivate_self")) if @user == current_user

      @user.deactivate!
      Activity.record!(:user_deactivated, email: @user.email)
      redirect_to settings_users_path, notice: t("flash.users.deactivated", email: @user.email)
    rescue ActiveRecord::RecordInvalid
      redirect_to settings_users_path, alert: @user.errors.full_messages.to_sentence
    end

    def reactivate
      @user.reactivate!
      Activity.record!(:user_reactivated, email: @user.email)
      redirect_to settings_users_path, notice: t("flash.users.reactivated", email: @user.email)
    end

    # For someone who lost their authenticator and backup codes.
    def reset_two_factor
      @user.disable_two_factor!
      Activity.record!(:two_factor_disabled, email: @user.email, reset_by: current_user.email)
      redirect_to settings_users_path, notice: t("flash.users.two_factor_reset", email: @user.email)
    end

    # Before the end of a lock after too many failed sign in attempts.
    def unlock
      @user.unlock_access!
      Activity.record!(:user_unlocked, email: @user.email)
      redirect_to settings_users_path, notice: t("flash.users.unlocked", email: @user.email)
    end

    private

    def set_user
      @user = User.find(params[:id])
    end
  end
end
