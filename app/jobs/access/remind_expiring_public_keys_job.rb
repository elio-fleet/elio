# Run every hour (config/recurring.yml): reminds of the keyring keys whose
# expiry date is near or past (public_key_expiring activity), so their owner
# rotates them. Sent through the notification channels subscribed to that kind.
class RemindExpiringPublicKeysJob < ApplicationJob
  queue_as :default

  def perform
    PublicKey.due_for_expiry_reminder.find_each(&:remind_expiry!)
  end
end
