module Settings
  # Invitations of Settings → Users: one or several addresses at once, resent
  # in one click once expired, revoked while pending. Emails go out in the
  # background (deliver_later); without emails, the links are copied by hand.
  class InvitationsController < ApplicationController
    require_permission :administer

    def create
      attributes = params.expect(invitation: %i[email role locale])
      emails = Invitation.split_emails(attributes.delete(:email))
      return redirect_to(settings_users_path, alert: t("flash.invitations.too_many", count: Invitation::MAX_AT_ONCE)) if emails.size > Invitation::MAX_AT_ONCE

      invitations = (emails.presence || [ "" ]).map { |email| Invitation.new(attributes.merge(email: email, invited_by: current_user)) }
      invited, failed = invitations.partition(&:save)
      invited.each { |invitation| send_invitation(invitation) }

      redirect_to settings_users_path, notice: (created_notice(invited) if invited.any?), alert: (failed_alert(failed) if failed.any?)
    end

    # An expired invitation, valid again with the same link.
    def resend
      invitation = Invitation.expired_unanswered.find(params[:id])
      invitation.renew!(by: current_user)
      send_invitation(invitation)
      redirect_to settings_users_path, notice: created_notice([ invitation ]), status: :see_other
    rescue ActiveRecord::RecordInvalid
      redirect_to settings_users_path, alert: failed_alert([ invitation ]), status: :see_other
    end

    def destroy
      invitation = Invitation.pending.find(params[:id])
      invitation.revoke!
      Activity.record!(:invitation_revoked, email: invitation.email)
      redirect_to settings_users_path, notice: t("flash.invitations.revoked", email: invitation.email), status: :see_other
    end

    private

    def send_invitation(invitation)
      Activity.record!(:user_invited, email: invitation.email, role: invitation.role)
      InvitationMailer.invite(invitation).deliver_later if Rails.configuration.x.mail_enabled
    end

    def created_notice(invitations)
      key = Rails.configuration.x.mail_enabled ? "emailed" : "created"
      if invitations.one?
        t("flash.invitations.#{key}", email: invitations.first.email)
      else
        t("flash.invitations.#{key}_many", count: invitations.size, emails: invitations.map(&:email).to_sentence)
      end
    end

    def failed_alert(invitations)
      errors = invitations.map do |invitation|
        messages = invitation.errors.full_messages.to_sentence
        invitation.email.present? ? "#{invitation.email} (#{messages})" : messages
      end
      t("flash.invitations.failed", errors: errors.join("; "))
    end
  end
end
