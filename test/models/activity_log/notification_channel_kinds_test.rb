require "test_helper"

class NotificationChannelKindsTest < ActiveSupport::TestCase
  def build(**attributes) = NotificationChannel.new({ name: "Canal", activity_kinds: %w[server_unreachable] }.merge(attributes))

  test "each kind checks its destination" do
    assert build(kind: "discord", webhook_url: "https://discord.com/api/webhooks/123456/abc_DEF-ghi").valid?
    assert_not build(kind: "discord", webhook_url: "https://hooks.slack.com/services/T/B/X").valid?
    assert build(kind: "webhook", webhook_url: "https://hooks.acme.fr/elio").valid?
    assert_not build(kind: "webhook", webhook_url: "http://hooks.acme.fr/elio").valid?
    assert_not build(kind: "webhook", webhook_url: "").valid?
    assert build(kind: "email", recipients: "Ops@Acme.fr; alice@acme.fr  ops@acme.fr").tap(&:validate).then { |channel| channel.valid? && channel.recipients == "ops@acme.fr, alice@acme.fr" }

    invalid = build(kind: "email", recipients: "ops@acme.fr, nope")
    assert_not invalid.valid?
    assert_includes invalid.errors[:recipients].sole, "nope"
    assert build(kind: "email", recipients: "").tap(&:validate).errors.added?(:recipients, :blank)
    assert_not build(kind: "email", recipients: (1..21).map { |i| "u#{i}@acme.fr" }.join(",")).valid?
    assert_not build(kind: "sms", webhook_url: "https://x").valid?
  end

  test "Slack-compatible services (Mattermost, Rocket.Chat): any HTTPS address, the Slack message format, mentions" do
    channel = build(kind: "slack_compatible", webhook_url: "https://chat.acme.fr/hooks/abc123")
    assert channel.valid?
    assert_equal [ Notifications::Slack, true ], [ channel.notifier, channel.mentions? ]
    assert_not build(kind: "slack_compatible", webhook_url: "http://chat.lan/hooks/abc123").valid?
  end

  test "plain HTTP only when allowed on the channel, for a generic or Slack-compatible webhook" do
    assert build(kind: "webhook", webhook_url: "http://n8n.lan:5678/webhook/elio", allow_http: true).valid?
    assert build(kind: "slack_compatible", webhook_url: "http://chat.lan/hooks/abc", allow_http: true).valid?
    assert_not build(kind: "webhook", webhook_url: "ftp://n8n.lan/elio", allow_http: true).valid?
    slack = build(kind: "slack", webhook_url: SlackHelpers::WEBHOOK, allow_http: true).tap(&:validate)
    assert_not slack.allow_http, "never for Slack or Discord"
  end

  test "a webhook channel gets a signing secret, stored encrypted" do
    channel = build(kind: "webhook", webhook_url: "https://hooks.acme.fr/elio")
    channel.save!

    assert_match(/\A\h{64}\z/, channel.signing_secret)
    raw = NotificationChannel.connection.select_value("SELECT signing_secret FROM notification_channels WHERE id = #{channel.id}")
    assert_not_includes raw, channel.signing_secret
    assert_nil build(kind: "slack", webhook_url: SlackHelpers::WEBHOOK).tap(&:validate).signing_secret
  end

  test "labels, notifiers and masked destinations" do
    assert_equal [ "Discord", Notifications::Discord ], build(kind: "discord").then { |channel| [ channel.kind_label, channel.notifier ] }
    assert_equal Notifications::Email, build(kind: "email").notifier
    assert_equal "ops@acme.fr", build(kind: "email", recipients: "ops@acme.fr").tap(&:validate).masked_destination
    assert_equal "https://discord.com/api/webhook…", build(kind: "discord", webhook_url: "https://discord.com/api/webhooks/1/secret").masked_destination
    assert build(kind: "slack").mentions?
    assert_not build(kind: "webhook").mentions?
  end
end
