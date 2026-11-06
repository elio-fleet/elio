require "openssl"

# Sends events to a generic HTTPS webhook as JSON. Each request is signed:
# X-Elio-Timestamp: <unix seconds> and
# X-Elio-Signature: sha256=<hex HMAC SHA-256 of "<timestamp>.<raw body)>",
# with the channel's signing secret>: the receiver checks it comes from Elio
# and refuses old messages (replays), e.g. older than 5 minutes.
class Notifications::Webhook
  def self.deliver(channel, activity)
    post(channel, "activity", activity_data(activity))
  end

  # Several activities of one kind (NotificationBatch::Group): event
  # "activities", with every activity in `events`.
  def self.deliver_batch(channel, group)
    post(channel, "activities", { kind: group.kind, label: group.label, category: group.category, severity: group.severity, count: group.count,
                                  title: group.title, url: group.url, events: group.activities.map { |activity| activity_data(activity) } }.compact)
  end

  def self.activity_data(activity)
    { kind: activity.kind, label: activity.label, category: activity.category, severity: activity.severity, summary: activity.summary,
      server: activity.server_name, unix_user: activity.unix_user, author: activity.user&.email, created_at: activity.created_at.iso8601 }
  end

  def self.deliver_test(channel)
    post(channel, "test", { message: I18n.t("notifications.webhook.test", channel_name: channel.name) })
  end

  def self.deliver_digest(channel, digest)
    post(channel, "digest", { title: digest.title, lines: digest.lines, from: digest.from.iso8601, to: digest.to.iso8601, counts: digest.counts })
  end

  def self.post(channel, event, data)
    now = Time.current
    body = { event: event, sent_at: now.iso8601, data: data }.to_json
    timestamp = now.to_i.to_s
    Notifications::Http.post(channel.webhook_url, body, service: I18n.t("notifications.webhook.service"),
                             headers: { "X-Elio-Event" => event, "X-Elio-Delivery" => SecureRandom.uuid, "X-Elio-Timestamp" => timestamp,
                                        "X-Elio-Signature" => "sha256=#{signature(channel, timestamp, body)}" })
  end

  def self.signature(channel, timestamp, body) = OpenSSL::HMAC.hexdigest("SHA256", channel.signing_secret, "#{timestamp}.#{body}")
end
