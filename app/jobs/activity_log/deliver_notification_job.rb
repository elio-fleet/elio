# Sends one activity to one channel right away. If the channel is failing (or
# fails now), the activity waits in the channel's batch of its kind until the
# next attempt: a broken webhook is not hit once per notification.
class DeliverNotificationJob < ApplicationJob
  queue_as :notifications
  queue_with_priority NOTIFICATIONS_PRIORITY

  discard_on ActiveJob::DeserializationError

  def perform(channel, activity)
    return unless channel.enabled? && channel.subscribed_to?(activity.kind)
    return NotificationBatch.add!(channel, activity) unless channel.claim_attempt!

    channel.in_language { channel.notifier.deliver(channel, activity) }
    channel.record_delivery!
  rescue Notifications::DeliveryError => e
    channel.record_delivery!(error: e.message)
    NotificationBatch.add!(channel, activity) if channel.enabled?
  end
end
