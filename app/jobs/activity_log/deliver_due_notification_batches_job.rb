# Safety net, every 5 minutes: the batches whose delivery job was lost
# (restart of an in-memory queue, job deleted) are sent once they are well
# overdue. The batches delivered or failed for a month are deleted.
class DeliverDueNotificationBatchesJob < ApplicationJob
  queue_as :default

  # The delivery job retries for a few minutes on errors: leave it that time.
  GRACE = 15.minutes
  KEEP = 30.days

  def perform
    NotificationBatch.undelivered.where(send_at: ...GRACE.ago).find_each { |batch| DeliverNotificationBatchJob.perform_later(batch) }
    NotificationBatch.where(delivered_at: ...KEEP.ago).or(NotificationBatch.where(failed_at: ...KEEP.ago)).delete_all
  end
end
