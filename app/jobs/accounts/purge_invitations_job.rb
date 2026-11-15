# Every day (config/recurring.yml): forgets the invitations revoked or expired
# more than Invitation::KEPT ago (accepted ones are kept).
class PurgeInvitationsJob < ApplicationJob
  queue_as :default

  def perform
    Invitation.purgeable.in_batches.delete_all
  end
end
