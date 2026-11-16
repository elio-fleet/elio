# A destination for activity notifications: a Slack, Discord, Slack-compatible
# (Mattermost, Rocket.Chat: the Slack message format at any HTTPS address) or
# generic webhook (JSON signed with HMAC SHA-256), or email recipients. A
# generic or Slack-compatible webhook may use plain HTTP on the internal
# network when the administrator allows it on the channel (allow_http). Each channel
# picks the activity kinds it receives (Activity::KINDS), whether messages
# mention everyone (Slack, Discord), how long it groups the non-critical ones
# (by kind, and by server if asked), and whether it gets a daily digest.
# A failing channel backs off (1, 2, 4… minutes, an hour at most): what it
# cannot send meanwhile waits in its batches, and one attempt at a time is
# made; after a day without success it is turned off and an activity says so.
class NotificationChannel < ApplicationRecord
  include Localized
  localized # nil: the instance's language

  KINDS = %w[slack discord slack_compatible webhook email].freeze
  # Minutes the non-critical activities of a kind wait to leave as one message
  # (0: right away), a day at most. With group_by_server, one message per kind and server.
  MAX_GROUP_MINUTES = 24 * 60
  NOTIFIERS = { "slack" => "Notifications::Slack", "slack_compatible" => "Notifications::Slack", "discord" => "Notifications::Discord", "webhook" => "Notifications::Webhook", "email" => "Notifications::Email" }.freeze

  SLACK_WEBHOOK = %r{\Ahttps://hooks\.slack\.com/services/[A-Za-z0-9/_-]+\z}
  DISCORD_WEBHOOK = %r{\Ahttps://(?:(?:ptb|canary)\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+\z}
  EMAIL = URI::MailTo::EMAIL_REGEXP
  MAX_RECIPIENTS = 20
  BACKOFF_MAX = 1.hour
  GIVE_UP_AFTER = 24.hours
  # Time an attempt claims (claim_attempt!): the other jobs wait meanwhile.
  ATTEMPT_WINDOW = 1.minute

  encrypts :webhook_url
  encrypts :signing_secret

  normalizes :name, with: ->(value) { value.squish }
  normalizes :webhook_url, with: ->(value) { value.strip.presence }
  normalizes :recipients, with: ->(value) { value.split(/[\s,;]+/).compact_blank.map(&:downcase).uniq.join(", ").presence }
  normalizes :activity_kinds, with: ->(kinds) { Array(kinds).compact_blank.map(&:to_s).uniq }

  before_validation :generate_signing_secret, if: -> { kind == "webhook" && signing_secret.blank? }
  before_validation { self.allow_http = false unless kind.in?(%w[webhook slack_compatible]) }
  # Turned back on, or given a new destination: the next notification is tried right away.
  before_save :forget_failures, if: -> { will_save_change_to_enabled?(to: true) || will_save_change_to_webhook_url? || will_save_change_to_recipients? }

  has_many :notification_batches, dependent: :delete_all

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :group_minutes, numericality: { only_integer: true, in: 0..MAX_GROUP_MINUTES }
  validate :destination_must_match_kind
  validate :activity_kinds_must_be_known

  scope :enabled, -> { where(enabled: true) }

  # Enabled channels that receive this kind of activity.
  def self.subscribed_to(kind)
    enabled.where("activity_kinds @> ?", [ kind.to_s ].to_json)
  end

  def kind_label = self.class.kind_label(kind)

  def self.kind_label(kind) = I18n.t("notification_channel.kinds.#{kind}", default: kind.to_s)

  # Messages of the channel are written in its language, else the instance's.
  def delivery_locale = locale || AppSetting.current.default_locale

  def in_language(&) = I18n.with_locale(delivery_locale, &)

  def notifier = NOTIFIERS.fetch(kind).constantize

  def email? = kind == "email"

  def mentions? = %w[slack discord slack_compatible].include?(kind)

  def subscribed_to?(kind) = activity_kinds.include?(kind.to_s)

  def groups? = group_minutes.positive?

  def recipient_list = recipients.to_s.split(", ")

  # Destination shown in the UI: the secret part of a webhook is hidden.
  def masked_destination
    return recipients.to_s if email?

    uri = URI(webhook_url.to_s)
    "#{uri.scheme}://#{uri.host}#{uri.path.to_s.first(12)}…"
  rescue URI::InvalidURIError
    "…"
  end

  # The channel is failing and waits before its next attempt.
  def backing_off? = retry_at.present? && retry_at.future?

  # Wait after the n-th failure in a row: 1, 2, 4… minutes, BACKOFF_MAX at most.
  def self.backoff(failures) = [ ATTEMPT_WINDOW * (2**(failures - 1).clamp(0, 10)), BACKOFF_MAX ].min

  # True when a job may try to deliver now. While the channel fails, only one
  # job at a time gets it: the others see the channel backing off and leave
  # their activities in its batches.
  def claim_attempt!
    return true if retry_at.nil?
    return false if retry_at.future?

    claimed = self.class.where(id: id, retry_at: retry_at).update_all(retry_at: ATTEMPT_WINDOW.from_now) == 1
    reload
    claimed
  end

  # A success forgets the failures and sends what waited at once; a failure
  # pushes the next attempt further, and turns the channel off when it has
  # failed for GIVE_UP_AFTER.
  def record_delivery!(error: nil)
    now = Time.current
    if error
      failures = failure_count + 1
      update_columns(last_error: error, failure_count: failures, failing_since: failing_since || now, retry_at: now + self.class.backoff(failures))
      give_up! if enabled? && failing_since <= GIVE_UP_AFTER.ago
    else
      waited = failure_count.positive?
      update_columns(last_delivered_at: now, last_error: nil, failure_count: 0, failing_since: nil, retry_at: nil)
      send_waiting_batches if waited
    end
  end

  # Turned off by Elio (not by an administrator) after failing for too long.
  def given_up? = !enabled? && failing_since.present?

  private

  def give_up!
    update_columns(enabled: false, retry_at: nil)
    notification_batches.undelivered.update_all(failed_at: Time.current)
    Activity.record!(:notification_channel_disabled, user: nil, channel_name: name, error: last_error)
  end

  def send_waiting_batches
    notification_batches.undelivered.where(send_at: Time.current..).find_each do |batch|
      batch.update!(send_at: Time.current)
      DeliverNotificationBatchJob.perform_later(batch)
    end
  end

  def forget_failures
    self.failure_count = 0
    self.failing_since = nil
    self.retry_at = nil
  end

  def generate_signing_secret
    self.signing_secret = SecureRandom.hex(32)
  end

  def destination_must_match_kind
    case kind
    when "slack" then url_must_match(SLACK_WEBHOOK)
    when "discord" then url_must_match(DISCORD_WEBHOOK)
    when "webhook", "slack_compatible"
      uri = URI.parse(webhook_url.to_s) rescue nil
      allowed = uri.is_a?(URI::HTTPS) || (allow_http && uri.is_a?(URI::HTTP))
      errors.add(:webhook_url, webhook_url.blank? ? :blank : :invalid) unless allowed && uri.host.present?
    when "email"
      list = recipient_list
      if list.empty? then errors.add(:recipients, :blank)
      elsif list.size > MAX_RECIPIENTS then errors.add(:recipients, :too_many, count: MAX_RECIPIENTS)
      elsif (invalid = list.grep_v(EMAIL)).any? then errors.add(:recipients, :invalid_emails, emails: invalid.join(", "))
      end
    end
  end

  def url_must_match(format)
    if webhook_url.blank? then errors.add(:webhook_url, :blank)
    elsif !webhook_url.match?(format) then errors.add(:webhook_url, :invalid)
    end
  end

  def activity_kinds_must_be_known
    unknown = activity_kinds - Activity::KINDS.keys.map(&:to_s)
    errors.add(:activity_kinds, :inclusion) if unknown.any?
  end
end
