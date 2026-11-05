# A destination for activity notifications: a Slack, Discord or generic
# webhook (JSON signed with HMAC SHA-256), or email recipients. Each channel
# picks the activity kinds it receives (Activity::KINDS), whether messages
# mention everyone (Slack, Discord), and whether it gets a daily digest.
class NotificationChannel < ApplicationRecord
  include Localized
  localized # nil: the instance's language

  KINDS = %w[slack discord webhook email].freeze
  # Minutes the non-critical activities of a kind wait to leave as one message (0: right away).
  GROUP_MINUTES = [ 0, 5, 10, 15, 30, 60 ].freeze
  NOTIFIERS = { "slack" => "Notifications::Slack", "discord" => "Notifications::Discord", "webhook" => "Notifications::Webhook", "email" => "Notifications::Email" }.freeze

  SLACK_WEBHOOK = %r{\Ahttps://hooks\.slack\.com/services/[A-Za-z0-9/_-]+\z}
  DISCORD_WEBHOOK = %r{\Ahttps://(?:(?:ptb|canary)\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+\z}
  EMAIL = URI::MailTo::EMAIL_REGEXP
  MAX_RECIPIENTS = 20

  encrypts :webhook_url
  encrypts :signing_secret

  normalizes :name, with: ->(value) { value.squish }
  normalizes :webhook_url, with: ->(value) { value.strip.presence }
  normalizes :recipients, with: ->(value) { value.split(/[\s,;]+/).compact_blank.map(&:downcase).uniq.join(", ").presence }
  normalizes :activity_kinds, with: ->(kinds) { Array(kinds).compact_blank.map(&:to_s).uniq }

  before_validation :generate_signing_secret, if: -> { kind == "webhook" && signing_secret.blank? }

  has_many :notification_batches, dependent: :delete_all

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :group_minutes, inclusion: { in: GROUP_MINUTES }
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

  def mentions? = %w[slack discord].include?(kind)

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

  def record_delivery!(error: nil)
    update_columns(error ? { last_error: error } : { last_delivered_at: Time.current, last_error: nil })
  end

  private

  def generate_signing_secret
    self.signing_secret = SecureRandom.hex(32)
  end

  def destination_must_match_kind
    case kind
    when "slack" then url_must_match(SLACK_WEBHOOK)
    when "discord" then url_must_match(DISCORD_WEBHOOK)
    when "webhook"
      uri = URI.parse(webhook_url.to_s) rescue nil
      errors.add(:webhook_url, webhook_url.blank? ? :blank : :invalid) unless uri.is_a?(URI::HTTPS) && uri.host.present?
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
