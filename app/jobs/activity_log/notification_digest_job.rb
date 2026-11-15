# Every morning (config/recurring.yml): sends yesterday's digest to the
# enabled channels that asked for it, each by its own job.
class NotificationDigestJob < ApplicationJob
  queue_as :notifications
  queue_with_priority NOTIFICATIONS_PRIORITY

  retry_on Notifications::DeliveryError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first&.record_delivery!(error: error.message)
  end

  def perform(channel = nil)
    return NotificationChannel.enabled.where(daily_digest: true).find_each { |each_channel| self.class.perform_later(each_channel) } unless channel
    return unless channel.enabled? && channel.daily_digest?

    channel.in_language { channel.notifier.deliver_digest(channel, NotificationDigest.new) }
    channel.update_columns(last_digest_at: Time.current)
    channel.record_delivery!
  rescue Notifications::DeliveryError => e
    channel.record_delivery!(error: e.message)
    raise
  end
end
