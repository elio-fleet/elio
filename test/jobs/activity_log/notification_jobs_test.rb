require "test_helper"

class NotificationJobsTest < ActiveJob::TestCase
  include SlackHelpers
  include StubHelpers

  test "creating an activity enqueues its notification" do
    activity = Activity.record!(:key_added, server: servers(:web))
    assert_enqueued_with(job: NotifyActivityJob, args: [ activity ])
  end

  test "NotifyActivityJob delivers to each enabled channel subscribed to the kind" do
    ops = create_channel
    security = create_channel(name: "#security", activity_kinds: %w[unknown_key_detected])
    create_channel(name: "#paused", enabled: false)
    create_channel(name: "#keys", activity_kinds: %w[key_added])
    activity = Activity.record!(:unknown_key_detected, server: servers(:web))

    NotifyActivityJob.perform_now(activity)

    assert_enqueued_jobs 2, only: DeliverNotificationJob
    assert_enqueued_with(job: DeliverNotificationJob, args: [ ops, activity ])
    assert_enqueued_with(job: DeliverNotificationJob, args: [ security, activity ])
  end

  test "a channel's messages are written in its language, else the instance's" do
    english = create_channel(locale: "en", activity_kinds: %w[server_unreachable])
    french = create_channel(name: "#fr", activity_kinds: %w[server_unreachable])
    activity = Activity.record!(:server_unreachable, server: servers(:web))
    texts = []

    stub_method(Notifications::Slack, :post, ->(_channel, payload) { texts << payload.to_json }) do
      DeliverNotificationJob.perform_now(english, activity)
      DeliverNotificationJob.perform_now(french, activity)
    end

    assert_match "Server unreachable", texts.first
    assert_match "“Web” no longer answers", texts.first
    assert_match "Serveur injoignable", texts.last
    assert_match "« Web » ne répond plus", texts.last
  end

  test "DeliverNotificationJob sends the activity and records the delivery" do
    channel = create_channel
    activity = Activity.record!(:ssh_access_lost, server: servers(:web))
    delivered = []

    stub_method(Notifications::Slack, :deliver, ->(c, a) { delivered << [ c, a ] }) { DeliverNotificationJob.perform_now(channel, activity) }

    assert_equal [ [ channel, activity ] ], delivered
    assert_not_nil channel.reload.last_delivered_at
  end

  test "DeliverNotificationJob skips a channel paused or unsubscribed meanwhile" do
    channel = create_channel
    activity = Activity.record!(:ssh_access_lost, server: servers(:web))
    channel.update!(activity_kinds: %w[key_added])

    stub_method(Notifications::Slack, :deliver, ->(*) { flunk "should not deliver" }) { DeliverNotificationJob.perform_now(channel, activity) }
  end

  test "a failing channel keeps the activity for its next attempt instead of retrying each notification" do
    channel = create_channel
    attempts = 0
    failing = ->(*) { attempts += 1; raise Notifications::DeliveryError, "Slack a répondu 500" }

    travel_to Time.zone.parse("2026-11-05 10:00") do
      first = Activity.record!(:ssh_access_lost, server: servers(:web))
      stub_method(Notifications::Slack, :deliver, failing) { DeliverNotificationJob.perform_now(channel, first) }

      channel.reload
      assert_equal [ "Slack a répondu 500", 1, Time.zone.parse("2026-11-05 10:01") ], [ channel.last_error, channel.failure_count, channel.retry_at ]
      assert_no_enqueued_jobs only: DeliverNotificationJob
      batch = NotificationBatch.sole
      assert_equal [ first.id ], batch.activity_ids
      assert_equal channel.retry_at, batch.send_at

      # Ten more notifications while the channel backs off: no attempt, they join the batch.
      clear_enqueued_jobs
      10.times do
        activity = Activity.record!(:ssh_access_lost, server: servers(:web))
        NotifyActivityJob.perform_now(activity)
        stub_method(Notifications::Slack, :deliver, failing) { DeliverNotificationJob.perform_now(channel.reload, activity) }
      end
      assert_equal 1, attempts
      assert_equal 11, batch.reload.activity_ids.size
      assert_no_enqueued_jobs only: DeliverNotificationJob
    end
  end

  test "the wait grows after each failure, an hour at most" do
    assert_equal [ 1, 2, 4, 8, 16, 32, 60, 60 ], (1..8).map { |failures| NotificationChannel.backoff(failures) / 60 }
  end

  test "while a channel fails, only one job at a time may try" do
    channel = create_channel
    channel.update_columns(failure_count: 2, retry_at: 1.second.ago)
    twin = NotificationChannel.find(channel.id)

    assert channel.claim_attempt!
    assert_not twin.claim_attempt!
    assert channel.reload.backing_off?
  end

  test "a success forgets the failures and sends what waited at once" do
    channel = create_channel(group_minutes: 10)
    channel.update_columns(failure_count: 3, failing_since: 1.hour.ago, retry_at: 30.minutes.from_now)
    activity = Activity.record!(:unknown_key_detected, server: servers(:web))
    NotifyActivityJob.perform_now(activity)
    batch = NotificationBatch.sole
    clear_enqueued_jobs

    channel.reload.record_delivery!

    assert_equal [ 0, nil, nil ], [ channel.failure_count, channel.failing_since, channel.retry_at ]
    assert_enqueued_with(job: DeliverNotificationBatchJob, args: [ batch ])
    assert batch.reload.send_at <= Time.current
  end

  test "a channel failing for a day is turned off, its waiting batches dropped, and an activity says so" do
    channel = create_channel(group_minutes: 10)
    other = create_channel(name: "#admins", activity_kinds: %w[notification_channel_disabled])
    channel.update_columns(failure_count: 30, failing_since: 25.hours.ago, retry_at: 1.minute.ago)
    NotifyActivityJob.perform_now(Activity.record!(:unknown_key_detected, server: servers(:web)))
    batch = NotificationBatch.sole

    stub_method(Notifications::Slack, :deliver, ->(*) { raise Notifications::DeliveryError, "Slack a répondu 404" }) do
      DeliverNotificationBatchJob.perform_now(batch)
    end

    assert_not channel.reload.enabled?
    assert channel.given_up?
    assert batch.reload.failed_at
    activity = Activity.of_kind(:notification_channel_disabled).sole
    assert_equal "Canal de notification « #ops » désactivé après une journée d'échecs : Slack a répondu 404", activity.summary
    assert_enqueued_with(job: NotifyActivityJob, args: [ activity ])
    assert other.reload.enabled?

    channel.update!(enabled: true)
    assert_equal [ 0, nil, nil ], [ channel.failure_count, channel.failing_since, channel.retry_at ]
    assert_not channel.given_up?
  end

  test "notification jobs use their own queue, before the jobs already waiting" do
    [ NotifyActivityJob, DeliverNotificationJob, DeliverNotificationBatchJob, DeliverDueNotificationBatchesJob, NotificationDigestJob ].each do |job|
      assert_equal [ "notifications", ApplicationJob::NOTIFICATIONS_PRIORITY ], [ job.new.queue_name, job.new.priority ], job.name
    end
    assert_operator ApplicationJob::NOTIFICATIONS_PRIORITY, :<, Inventory::CollectJob.new.priority.to_i
  end
end
