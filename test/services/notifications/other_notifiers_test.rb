require "test_helper"

class Notifications::OtherNotifiersTest < ActiveSupport::TestCase
  include StubHelpers
  include ActionMailer::TestHelper

  setup do
    @activity = Activity.record!(:port_opened, server: servers(:web), user: nil, port: "3306/tcp", process: "mysql @everyone *bold*")
    @posts = []
    stub_method_until_teardown(Notifications::Http, :post, ->(url, body, service:, headers: {}) { @posts << { url: url, body: JSON.parse(body), service: service, headers: headers } })
  end

  def channel(kind, **attributes)
    defaults = { "discord" => { webhook_url: "https://discord.com/api/webhooks/1/abc" }, "webhook" => { webhook_url: "https://hooks.acme.fr/elio" },
                 "email" => { recipients: "ops@acme.fr" } }.fetch(kind)
    NotificationChannel.create!(name: kind, kind: kind, activity_kinds: %w[port_opened], **defaults, **attributes)
  end

  test "Discord: an embed coloured by severity, markdown and mentions neutralized" do
    Notifications::Discord.deliver(channel("discord"), @activity)

    post = @posts.sole
    assert_equal [ "https://discord.com/api/webhooks/1/abc", "Discord" ], post.values_at(:url, :service)
    embed = post[:body]["embeds"].sole
    assert_equal [ "Port public ouvert", 0xfab219 ], embed.values_at("title", "color")
    assert_includes embed["description"], "mysql @​everyone \\*bold\\*"
    assert_equal({ "parse" => [] }, post[:body]["allowed_mentions"])
    assert_nil post[:body]["content"]
  end

  test "Discord: @everyone only when the channel asks for it" do
    Notifications::Discord.deliver_test(channel("discord", mention_channel: true))

    assert_equal [ "@everyone", { "parse" => [ "everyone" ] } ], @posts.sole[:body].values_at("content", "allowed_mentions")
  end

  test "webhook: a JSON event signed with the channel secret" do
    hook = channel("webhook")

    Notifications::Webhook.deliver(hook, @activity)

    post = @posts.sole
    assert_equal "activity", post[:body]["event"]
    assert_equal [ "port_opened", "warning", "Web" ], post[:body]["data"].values_at("kind", "severity", "server")
    assert_equal "activity", post[:headers]["X-Elio-Event"]
    body = { event: "activity", sent_at: post[:body]["sent_at"], data: post[:body]["data"] }.to_json
    timestamp = post[:headers]["X-Elio-Timestamp"]
    assert_in_delta Time.current.to_i, timestamp.to_i, 2
    assert_equal "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", hook.signing_secret, "#{timestamp}.#{body}")}", post[:headers]["X-Elio-Signature"],
                 "the timestamp is signed with the body (a replayed message can be refused)"
  end

  test "email: the activity, a test and a digest to the recipients" do
    email = channel("email", recipients: "ops@acme.fr, alice@acme.fr")
    ActionMailer::Base.deliveries.clear

    assert_emails(3) do
      Notifications::Email.deliver(email, @activity)
      Notifications::Email.deliver_test(email)
      Notifications::Email.deliver_digest(email, NotificationDigest.new(from: 1.hour.ago, to: Time.current))
    end
    mail = ActionMailer::Base.deliveries.first
    assert_equal [ "ops@acme.fr", "alice@acme.fr" ], mail.to
    assert_equal "[Elio] Port public ouvert : Port 3306/tcp ouvert publiquement sur « Web » (mysql @everyone *bold*)", mail.subject
    assert_match "Résumé Elio du", ActionMailer::Base.deliveries.last.subject
  end

  test "email: an error without SMTP" do
    Rails.configuration.x.mail_enabled = false
    error = assert_raises(Notifications::DeliveryError) { Notifications::Email.deliver_test(channel("email")) }
    assert_match "SMTP_", error.message
  ensure
    Rails.configuration.x.mail_enabled = true
  end

  test "the digest sums up the fleet and the warnings of the period" do
    Activity.record!(:server_back_online, server: servers(:db), user: nil)
    travel_to(2.days.ago) { Activity.record!(:health_critical, server: servers(:db), user: nil, reasons: [ "old" ]) }

    digest = NotificationDigest.new(from: 1.hour.ago, to: Time.current)

    assert_equal({ critical: 0, warning: 1, info: 1 }, digest.counts)
    assert_match(/\AParc : \d\/3 en ligne/, digest.lines.first)
    assert_includes digest.lines, "- Port public ouvert : Port 3306/tcp ouvert publiquement sur « Web » (mysql @everyone *bold*)"
    assert_equal [ "Rien à signaler." ], NotificationDigest.new(from: 10.days.ago, to: 9.days.ago).lines.last(1)
  end
end
