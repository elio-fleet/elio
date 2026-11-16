# Every day (config/recurring.yml): forgets the activities older than the
# retention (ELIO_ACTIVITY_RETENTION_DAYS, 365 days by default; 0 = keep
# everything): the log does not grow forever and personal data (authors'
# emails) is not kept longer than needed.
class PurgeActivitiesJob < ApplicationJob
  queue_as :default

  def self.retention
    days = Elio::Env.integer("ELIO_ACTIVITY_RETENTION_DAYS")
    days.positive? ? days.days : nil
  end

  def perform
    retention = self.class.retention or return

    Activity.where(created_at: ...retention.ago).in_batches.delete_all
  end
end
