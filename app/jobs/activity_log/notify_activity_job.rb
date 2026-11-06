# Sends an activity to every enabled channel subscribed to its kind. Each
# channel is delivered by its own job so one failing webhook does not block
# or repeat the others. Critical activities, and channels that do not group
# (group_minutes 0), are sent right away; the others wait in the channel's
# batch of their kind (NotificationBatch).
class NotifyActivityJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(activity)
    NotificationChannel.subscribed_to(activity.kind).find_each do |channel|
      if activity.severity == :critical || channel.group_minutes.zero?
        DeliverNotificationJob.perform_later(channel, activity)
      else
        NotificationBatch.add!(channel, activity)
      end
    end
  end
end
