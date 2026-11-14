module Settings
  class InvitationsController < ApplicationController
    require_permission :administer

    def create
      @invitation = Invitation.new(params.expect(invitation: %i[email role locale]).merge(invited_by: current_user))

      if @invitation.save
        Activity.record!(:user_invited, email: @invitation.email, role: @invitation.role)
        if Rails.configuration.x.mail_enabled
          InvitationMailer.invite(@invitation).deliver_later
          redirect_to settings_users_path, notice: t("flash.invitations.emailed", email: @invitation.email)
        else
          redirect_to settings_users_path, notice: t("flash.invitations.created", email: @invitation.email)
        end
      else
        redirect_to settings_users_path, alert: t("flash.invitations.failed", errors: @invitation.errors.full_messages.to_sentence)
      end
    end

    def destroy
      invitation = Invitation.pending.find(params[:id])
      invitation.revoke!
      Activity.record!(:invitation_revoked, email: invitation.email)
      redirect_to settings_users_path, notice: t("flash.invitations.revoked", email: invitation.email), status: :see_other
    end
  end
end
