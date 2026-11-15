# Sends a NotificationBatch once its waiting time is over: one message for
# all its activities (or the activity alone if it is the only one). While the
# channel fails, the batch waits for the channel's next attempt
# (NotificationChannel#retry_at) instead of retrying on its own.
class DeliverNotificationBatchJob < ApplicationJob
  queue_as :notifications
  queue_with_priority NOTIFICATIONS_PRIORITY

  discard_on ActiveJob::DeserializationError

  def perform(batch)
    channel = batch.channel
    return unless batch.close!
    return batch.update!(failed_at: Time.current) unless channel.enabled?
    return batch.postpone!(channel.retry_at) unless channel.claim_attempt!

    batch.deliver!
  rescue Notifications::DeliveryError => e
    channel.record_delivery!(error: e.message)
    batch.postpone!(channel.retry_at) if channel.enabled?
  end
end
