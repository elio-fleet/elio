# Run every minute (config/recurring.yml): reminds of the temporary accesses
# about to end (key_expiring activity), and, as a safety net, expires those
# whose scheduled job was lost.
class ExpireTemporaryAccessesJob < ApplicationJob
  queue_as :default

  def perform
    TemporaryAccess.due_for_reminder.find_each(&:remind!)
    TemporaryAccess.expired.find_each { |access| ExpireTemporaryAccessJob.perform_later(access) }
  end
end
