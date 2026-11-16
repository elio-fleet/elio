require "test_helper"

# Grouped notifications (phase 13.7): by channel and kind, critical ones right away.
class NotificationBatchesTest < ActiveJob::TestCase
  include SlackHelpers
  include StubHelpers
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    @channel = create_channel(group_minutes: 10, activity_kinds: %w[unknown_key_detected key_disappeared ssh_access_lost])
  end

  # The emails sent here must not be seen by the next test of the worker.
  teardown { ActionMailer::Base.deliveries.clear }

  def notify(kind, server: servers(:web), **data) = Activity.record!(kind, server: server, user: nil, **data).tap { |activity| NotifyActivityJob.perform_now(activity) }

  test "non-critical activities wait in one batch per kind, a critical one leaves right away" do
    travel_to Time.zone.parse("2026-11-05 10:00") do
      first = notify(:unknown_key_detected, key_name: "bob")
      second = notify(:unknown_key_detected, key_name: "carol")
      gone = notify(:key_disappeared, key_name: "dave")
      critical = notify(:ssh_access_lost)

      batches = NotificationBatch.order(:id).to_a
      assert_equal [ [ "unknown_key_detected", [ first.id, second.id ] ], [ "key_disappeared", [ gone.id ] ] ], batches.map { |batch| [ batch.kind, batch.activity_ids ] }
      assert_equal [ Time.zone.parse("2026-11-05 10:10") ] * 2, batches.map(&:send_at)
      assert_enqueued_jobs 2, only: DeliverNotificationBatchJob # one per batch, scheduled when it opens
      assert_enqueued_with(job: DeliverNotificationBatchJob, args: [ batches.first ], at: Time.zone.parse("2026-11-05 10:10"))
      assert_enqueued_with(job: DeliverNotificationJob, args: [ @channel, critical ])
    end
  end

  test "a channel that does not group sends each activity right away" do
    @channel.update!(group_minutes: 0)
    activity = notify(:unknown_key_detected)
    assert_equal 0, NotificationBatch.count
    assert_enqueued_with(job: DeliverNotificationJob, args: [ @channel, activity ])
  end

  test "the batch leaves as one message; an activity arriving after it closed opens a new one" do
    3.times { |index| notify(:unknown_key_detected, key_name: "key-#{index}") }
    batch = NotificationBatch.sole
    payloads = []

    stub_method(Notifications::Slack, :post, ->(_url, payload) { payloads << payload }) do
      DeliverNotificationBatchJob.perform_now(batch)
      DeliverNotificationBatchJob.perform_now(batch) # a second run (the sweep) sends nothing more
    end

    assert_equal 1, payloads.size
    assert_equal ":warning: *3 × Clé inconnue détectée*\n1 serveur touché : Web\n• Clé inconnue « key-0 » trouvée sur « Web »\n• Clé inconnue « key-1 » trouvée sur « Web »\n• Clé inconnue « key-2 » trouvée sur « Web »",
                 payloads.first[:text]
    assert batch.reload.delivered_at
    assert @channel.reload.last_delivered_at

    late = notify(:unknown_key_detected, key_name: "late")
    assert_equal [ late.id ], NotificationBatch.open.sole.activity_ids
  end

  test "a channel may group by server too: one batch per kind and server" do
    first_web = notify(:unknown_key_detected, key_name: "a")
    first_db = notify(:unknown_key_detected, key_name: "b", server: servers(:db))
    assert_equal [ [ first_web.id, first_db.id ] ], NotificationBatch.pluck(:activity_ids)
    assert_nil NotificationBatch.sole.server_id
    NotificationBatch.delete_all
    clear_enqueued_jobs

    @channel.update!(group_by_server: true)
    web = [ notify(:unknown_key_detected, key_name: "c"), notify(:unknown_key_detected, key_name: "d") ]
    db = notify(:unknown_key_detected, key_name: "e", server: servers(:db))
    serverless = notify(:unknown_key_detected, key_name: "f", server: nil)
    other_kind = notify(:key_disappeared, key_name: "g")

    batches = NotificationBatch.order(:id).map { |batch| [ batch.kind, batch.server_id, batch.activity_ids ] }
    assert_equal [ [ "unknown_key_detected", servers(:web).id, web.map(&:id) ], [ "unknown_key_detected", servers(:db).id, [ db.id ] ],
                   [ "unknown_key_detected", nil, [ serverless.id ] ], [ "key_disappeared", servers(:web).id, [ other_kind.id ] ] ], batches
    assert_enqueued_jobs 4, only: DeliverNotificationBatchJob
  end

  test "a grouped message starts with the servers affected, the first ones named" do
    activities = %w[s1 s2 s3 s4 s5 s6 s7 s1].map { |name| Activity.record!(:unknown_key_detected, user: nil, server_name: name, key_name: "k") }
    assert_equal "7 serveurs touchés : s1, s2, s3, s4, s5 et 2 autres", NotificationBatch::Group.new("unknown_key_detected", activities).summary
    assert_equal "1 serveur touché : s1", NotificationBatch::Group.new("unknown_key_detected", activities.first(1)).summary
    I18n.with_locale(:en) { assert_equal "2 servers affected: s1, s2", NotificationBatch::Group.new("unknown_key_detected", activities.first(2)).summary }
    assert_nil NotificationBatch::Group.new("automation_run", [ Activity.record!(:automation_run, user: nil) ]).summary
  end

  test "a batch of one activity is sent as that activity" do
    activity = notify(:unknown_key_detected, key_name: "bob")
    delivered = []
    stub_method(Notifications::Slack, :deliver, ->(channel, sent) { delivered << [ channel, sent ] }) do
      DeliverNotificationBatchJob.perform_now(NotificationBatch.sole)
    end
    assert_equal [ [ @channel, activity ] ], delivered
  end

  test "long batches are cut, with a link to the activities when Elio knows its address" do
    12.times { |index| notify(:unknown_key_detected, key_name: "key-#{index}") }
    group = NotificationBatch::Group.new("unknown_key_detected", NotificationBatch.sole.activities)
    assert_equal 11, group.lines.size
    assert_equal "…et 2 autres", group.lines.last
    assert_nil group.url

    with_default_url_options(host: "elio.example.com", protocol: "https") do
      assert_equal "https://elio.example.com/journal?kind=unknown_key_detected", group.url
    end
  end

  test "each notifier writes a grouped message, in the channel's language" do
    @channel.update!(locale: "en")
    notify(:unknown_key_detected, key_name: "key-0")
    notify(:unknown_key_detected, key_name: "key-1", server: servers(:db))
    batch = NotificationBatch.sole

    discord = NotificationChannel.create!(name: "discord", kind: "discord", webhook_url: "https://discord.com/api/webhooks/1/abc", activity_kinds: %w[unknown_key_detected], group_minutes: 5, locale: "en")
    webhook = NotificationChannel.create!(name: "hook", kind: "webhook", webhook_url: "https://hooks.example.com/elio", activity_kinds: %w[unknown_key_detected], group_minutes: 5, locale: "en")
    sent = []
    stub_method(Notifications::Http, :post, ->(url, body, **) { sent << [ url, JSON.parse(body) ] }) do
      @channel.in_language { Notifications::Slack.deliver_batch(@channel, NotificationBatch::Group.new(batch.kind, batch.activities)) }
      discord.in_language { Notifications::Discord.deliver_batch(discord, NotificationBatch::Group.new(batch.kind, batch.activities)) }
      webhook.in_language { Notifications::Webhook.deliver_batch(webhook, NotificationBatch::Group.new(batch.kind, batch.activities)) }
    end

    slack, embed, hook = sent.map(&:last)
    assert_match "2 × Unknown key detected", slack["text"]
    assert_equal "2 × Unknown key detected", embed["embeds"].first["title"].delete("\\")
    assert_match "key-1", embed["embeds"].first["description"]
    assert_match "\n2 servers affected: Web, Database\n", slack["text"]
    assert embed["embeds"].first["description"].start_with?("2 servers affected: Web, Database\n")
    assert_equal "activities", hook["event"]
    assert_equal "2 servers affected: Web, Database", hook["data"]["summary"]
    assert_equal %w[Web Database], hook["data"]["servers"]
    assert_equal 2, hook["data"]["count"]
    assert_equal %w[unknown_key_detected unknown_key_detected], hook["data"]["events"].map { |event| event["kind"] }
  end

  test "an email channel gets one email for the batch" do
    channel = NotificationChannel.create!(name: "mail", kind: "email", recipients: "ops@example.com", activity_kinds: %w[unknown_key_detected], group_minutes: 10)
    2.times { |index| notify(:unknown_key_detected, key_name: "key-#{index}") }
    batch = NotificationBatch.find_by!(channel: channel)

    assert_emails 1 do
      DeliverNotificationBatchJob.perform_now(batch)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal "[Elio] 2 × Clé inconnue détectée", mail.subject
    assert_match "- Clé inconnue « key-1 » trouvée sur « Web »", mail.body.to_s
    assert_match "1 serveur touché : Web\n", mail.body.to_s
  end

  test "an error is recorded and tried again at the channel's next attempt; a paused or unsubscribed channel sends nothing" do
    notify(:unknown_key_detected)
    batch = NotificationBatch.sole
    stub_method(Notifications::Slack, :post, ->(*) { raise Notifications::DeliveryError, "Slack: 500" }) do
      DeliverNotificationBatchJob.perform_now(batch)
    end
    assert_equal "Slack: 500", @channel.reload.last_error
    assert_nil batch.reload.delivered_at
    assert batch.closed_at
    assert_equal @channel.retry_at, batch.send_at
    assert_enqueued_with(job: DeliverNotificationBatchJob, args: [ batch ], at: @channel.retry_at)

    # Its job runs while the channel still backs off: postponed again, no attempt.
    clear_enqueued_jobs
    stub_method(Notifications::Slack, :post, ->(*) { flunk "backing off" }) { DeliverNotificationBatchJob.perform_now(batch) }
    assert_enqueued_with(job: DeliverNotificationBatchJob, args: [ batch ])
    @channel.update_columns(retry_at: nil, failure_count: 0)

    notify(:key_disappeared)
    @channel.update!(activity_kinds: %w[unknown_key_detected])
    stub_method(Notifications::Slack, :post, ->(*) { flunk "unsubscribed" }) { DeliverNotificationBatchJob.perform_now(NotificationBatch.find_by!(kind: "key_disappeared")) }

    notify(:unknown_key_detected)
    @channel.update!(enabled: false)
    paused = NotificationBatch.open.sole
    stub_method(Notifications::Slack, :post, ->(*) { flunk "paused" }) { DeliverNotificationBatchJob.perform_now(paused) }
    assert paused.reload.failed_at
  end

  test "the sweep sends the batches whose job was lost, then forgets the old ones" do
    notify(:unknown_key_detected)
    batch = NotificationBatch.sole
    clear_enqueued_jobs

    travel 30.minutes do
      DeliverDueNotificationBatchesJob.perform_now
    end
    assert_enqueued_with(job: DeliverNotificationBatchJob, args: [ batch ])

    batch.update!(delivered_at: 31.days.ago)
    DeliverDueNotificationBatchesJob.perform_now
    assert_not NotificationBatch.exists?(batch.id)
  end

  test "an activity added while the batch is being closed opens a new batch" do
    notify(:unknown_key_detected)
    batch = NotificationBatch.sole
    batch.update!(closed_at: Time.current) # the delivery job closed it meanwhile
    late = notify(:unknown_key_detected, key_name: "late")
    assert_equal [ late.id ], NotificationBatch.open.sole.activity_ids
    assert_not_includes batch.reload.activity_ids, late.id
  end

  def with_default_url_options(options)
    config = Rails.application.config.action_mailer
    previous = config.default_url_options
    config.default_url_options = options
    yield
  ensure
    config.default_url_options = previous
  end
end
