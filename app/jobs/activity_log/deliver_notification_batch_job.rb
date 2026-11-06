# Sends a NotificationBatch once its waiting time is over: one message for
# all its activities (or the activity alone if it is the only one).
class DeliverNotificationBatchJob < ApplicationJob
  queue_as :default

  retry_on Notifications::DeliveryError, wait: :polynomially_longer, attempts: 5 do |job, error|
    batch = job.arguments.first
    batch.update!(failed_at: Time.current)
    batch.channel.record_delivery!(error: error.message)
  end
  discard_on ActiveJob::DeserializationError

  def perform(batch)
    return unless batch.close!
    return batch.update!(failed_at: Time.current) unless batch.channel.enabled?

    batch.deliver!
  rescue Notifications::DeliveryError => e
    batch.channel.record_delivery!(error: e.message)
    raise
  end
end
