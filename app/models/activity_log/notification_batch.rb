# Activities of one kind waiting to leave a notification channel as a single
# message (channel.group_minutes). Critical activities never wait (see
# NotifyActivityJob). Open while activities are added; the delivery job
# closes it (so nothing added meanwhile is lost: it opens a new batch), then
# marks it delivered or failed. Kept in the database: a restart loses nothing
# (DeliverDueNotificationBatchesJob picks up what was not delivered).
class NotificationBatch < ApplicationRecord
  # Summaries listed in a grouped message; the rest are counted.
  MAX_LISTED = 10

  belongs_to :channel, class_name: "NotificationChannel", foreign_key: :notification_channel_id

  scope :open, -> { where(closed_at: nil) }
  scope :undelivered, -> { where(delivered_at: nil, failed_at: nil) }

  # Adds the activity to the open batch of its kind on this channel, opening
  # one (and scheduling its delivery) if needed.
  def self.add!(channel, activity)
    opened = false
    batch = channel.with_lock do
      open.find_by(channel: channel, kind: activity.kind)&.tap { |found| found.update!(activity_ids: found.activity_ids | [ activity.id ]) } ||
        create!(channel: channel, kind: activity.kind, activity_ids: [ activity.id ], send_at: channel.group_minutes.minutes.from_now).tap { opened = true }
    end
    DeliverNotificationBatchJob.set(wait_until: batch.send_at).perform_later(batch) if opened
    batch
  end

  # Takes the batch out of the open ones: returns false if it was delivered already.
  def close!
    with_lock do
      return false if delivered_at || failed_at

      update!(closed_at: Time.current) unless closed_at
      true
    end
  end

  def activities = Activity.where(id: activity_ids).includes(:user, :server, :public_key).order(:created_at, :id).to_a

  def deliver!
    list = activities
    # All deleted (purge) or the channel unsubscribed meanwhile: nothing to send.
    return update!(delivered_at: Time.current) if list.empty? || !channel.subscribed_to?(kind)

    channel.in_language do
      list.one? ? channel.notifier.deliver(channel, list.first) : channel.notifier.deliver_batch(channel, Group.new(kind, list))
    end
    update!(delivered_at: Time.current)
    channel.record_delivery!
  end

  # What a notifier receives for a grouped message.
  class Group
    attr_reader :kind, :activities

    def initialize(kind, activities)
      @kind = kind
      @activities = activities
    end

    def count = activities.size
    def definition = Activity::KINDS.fetch(kind.to_sym)
    def label = definition.label
    def severity = definition.severity
    def category = definition.category

    # "12 × Fixable vulnerability"
    def title = I18n.t("notifications.batch.title", count: count, label: label)

    # The summaries (MAX_LISTED at most), then "…and 3 more".
    def lines
      listed = activities.first(MAX_LISTED).map(&:summary)
      listed << I18n.t("notifications.batch.more", count: count - MAX_LISTED) if count > MAX_LISTED
      listed
    end

    def servers = activities.filter_map(&:server_name).uniq

    # Link to the activity page filtered on the kind, when Elio knows its address (ELIO_HOST).
    def url
      options = Rails.application.config.action_mailer.default_url_options || {}
      return if options[:host].blank? || options[:host] == "example.com"

      Rails.application.routes.url_helpers.activities_url(kind: kind, **options)
    end
  end
end
