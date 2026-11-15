require "test_helper"

class PurgeInvitationsJobTest < ActiveJob::TestCase
  test "forgets the invitations revoked or expired more than 30 days ago" do
    old = Invitation.create!(email: "old@example.com", invited_by: users(:one)).tap { |i| i.update_columns(expires_at: 31.days.ago) }
    recent = Invitation.create!(email: "recent@example.com", invited_by: users(:one)).tap { |i| i.update_columns(expires_at: 1.day.ago) }

    PurgeInvitationsJob.perform_now

    assert_not Invitation.exists?(old.id)
    assert Invitation.exists?(recent.id)
  end

  test "runs every day in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each { |environment| assert_equal "PurgeInvitationsJob", recurring.dig(environment, "purge_invitations", "class") }
  end
end
