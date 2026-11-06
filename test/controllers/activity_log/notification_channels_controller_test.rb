require "test_helper"

class NotificationChannelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SlackHelpers
  include StubHelpers

  def valid_params(**overrides)
    { notification_channel: { name: "#ops", webhook_url: WEBHOOK, mention_channel: "1", enabled: "1",
                              activity_kinds: [ "", "unknown_key_detected", "key_added" ] }.merge(overrides) }
  end

  test "every action requires authentication" do
    channel = create_channel

    get new_settings_notification_channel_path
    assert_redirected_to new_user_session_path
    post settings_notification_channels_path, params: valid_params(name: "#new")
    assert_redirected_to new_user_session_path
    patch settings_notification_channel_path(channel), params: valid_params(name: "#hacked")
    assert_redirected_to new_user_session_path
    delete settings_notification_channel_path(channel)
    assert_redirected_to new_user_session_path
    post test_settings_notification_channel_path(channel)
    assert_redirected_to new_user_session_path
    assert_equal "#ops", channel.reload.name
  end

  test "the notifications page lists the channels without revealing the webhook" do
    create_channel(mention_channel: true, last_error: "Slack a répondu 404")
    sign_in users(:one)

    get settings_notifications_path

    assert_select "section.notification-channel", 1 do
      assert_select "h2", text: /#ops/
      assert_select ".channel-state", "Actif"
      assert_select ".channel-mention", "@channel"
      assert_select ".channel-kind", 2
      assert_select ".channel-error", text: /Slack a répondu 404/
    end
    assert_no_match "XXXXXXXXXXXXXXXX", response.body
    assert_select "a[href=?]", new_settings_notification_channel_path, text: "Ajouter un canal"
  end

  test "empty state" do
    sign_in users(:one)
    get settings_notifications_path
    assert_select "p", text: "Aucun canal de notification pour le moment."
  end

  test "new preselects the warnings and critical activities" do
    sign_in users(:one)

    get new_settings_notification_channel_path

    assert_select "input[type=checkbox][name='notification_channel[activity_kinds][]'][value=unknown_key_detected][checked]"
    assert_select "input[type=checkbox][name='notification_channel[activity_kinds][]'][value=ssh_access_lost][checked]"
    assert_select "input[type=checkbox][name='notification_channel[activity_kinds][]'][value=key_added]:not([checked])"
    assert_select ".activity-kind-group", Activity::CATEGORIES.size
    assert_select "nav.settings-nav a[aria-current=page]", "Notifications"
  end

  test "create saves the channel" do
    sign_in users(:one)

    post settings_notification_channels_path, params: valid_params

    channel = NotificationChannel.sole
    assert_equal [ "#ops", WEBHOOK, %w[unknown_key_detected key_added], true, true ],
                 [ channel.name, channel.webhook_url, channel.activity_kinds, channel.mention_channel, channel.enabled ]
    assert_redirected_to settings_notifications_path
  end

  test "create with no activity selected subscribes to nothing" do
    sign_in users(:one)
    post settings_notification_channels_path, params: valid_params(activity_kinds: [ "" ])
    assert_equal [], NotificationChannel.sole.activity_kinds
  end

  test "create re-renders the form with errors" do
    sign_in users(:one)

    post settings_notification_channels_path, params: valid_params(webhook_url: "https://evil.example/hook")

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "L'URL du webhook n'est pas valide"
    assert_equal 0, NotificationChannel.count
  end

  test "edit never sends the webhook back" do
    channel = create_channel
    sign_in users(:one)

    get edit_settings_notification_channel_path(channel)

    assert_select "input[type=password][name='notification_channel[webhook_url]']:not([value])"
    assert_no_match "XXXXXXXXXXXXXXXX", response.body
  end

  test "update keeps the webhook when left blank" do
    channel = create_channel
    sign_in users(:one)

    patch settings_notification_channel_path(channel), params: valid_params(name: "#ops2", webhook_url: "", mention_channel: "0", activity_kinds: [ "", "key_removed" ])

    channel.reload
    assert_equal [ "#ops2", WEBHOOK, false, %w[key_removed] ], [ channel.name, channel.webhook_url, channel.mention_channel, channel.activity_kinds ]
    assert_redirected_to settings_notifications_path
  end

  test "update can replace the webhook" do
    channel = create_channel
    sign_in users(:one)
    new_webhook = "https://hooks.slack.com/services/T111/B111/YYYY"

    patch settings_notification_channel_path(channel), params: valid_params(webhook_url: new_webhook)

    assert_equal new_webhook, channel.reload.webhook_url
  end

  test "destroy deletes the channel" do
    channel = create_channel
    sign_in users(:one)

    delete settings_notification_channel_path(channel)

    assert_equal 0, NotificationChannel.count
    assert_redirected_to settings_notifications_path
  end

  test "test sends a test message and reports the result" do
    channel = create_channel
    sign_in users(:one)

    stub_method(Notifications::Slack, :deliver_test, ->(c) { assert_equal channel, c }) do
      post test_settings_notification_channel_path(channel)
    end
    assert_equal "Message de test envoyé à « #ops ».", flash[:notice]
    assert_not_nil channel.reload.last_delivered_at

    stub_method(Notifications::Slack, :deliver_test, ->(*) { raise Notifications::DeliveryError, "Slack a répondu 404 : no_service" }) do
      post test_settings_notification_channel_path(channel)
    end
    assert_equal "Échec de l'envoi à « #ops » : Slack a répondu 404 : no_service", flash[:alert]
    assert_equal "Slack a répondu 404 : no_service", channel.reload.last_error
  end

  test "creates a Discord, a webhook or an email channel, with the daily digest" do
    sign_in users(:one)

    post settings_notification_channels_path, params: { notification_channel: { name: "Equipe", kind: "email", recipients: "ops@acme.fr", daily_digest: "1", activity_kinds: [ "server_unreachable" ] } }
    assert_redirected_to settings_notifications_path
    channel = NotificationChannel.find_by!(name: "Equipe")
    assert_equal [ "email", "ops@acme.fr", true ], [ channel.kind, channel.recipients, channel.daily_digest ]

    post settings_notification_channels_path, params: { notification_channel: { name: "Hook", kind: "webhook", webhook_url: "https://hooks.acme.fr/elio", activity_kinds: [ "server_unreachable" ] } }
    get settings_notifications_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(NotificationChannel.find_by!(name: "Hook"))}" do
      assert_select ".channel-kind-label", "Webhook (JSON signé)"
      assert_select "details.channel-secret input[value=?]", NotificationChannel.find_by!(name: "Hook").signing_secret
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(channel)} .channel-digest", "résumé quotidien"
  end

  test "the form shows the fields of each kind" do
    sign_in users(:one)
    get new_settings_notification_channel_path

    assert_select "form[data-controller=kind-fields]" do
      assert_select "input[type=radio][name='notification_channel[kind]']", 4
      assert_select "[data-kind-fields-target=field][data-kinds='slack discord webhook'] input[name='notification_channel[webhook_url]']"
      assert_select "[data-kind-fields-target=field][data-kinds=email] input[name='notification_channel[recipients]']"
      assert_select "input[type=checkbox][name='notification_channel[daily_digest]']"
    end
  end

  test "the grouping of the notifications is chosen per channel, 10 minutes for a new one" do
    sign_in users(:one)
    get new_settings_notification_channel_path
    assert_select "select[name='notification_channel[group_minutes]'] option[selected][value='10']"

    post settings_notification_channels_path, params: valid_params(group_minutes: "30")
    channel = NotificationChannel.find_by!(name: "#ops")
    assert_equal 30, channel.group_minutes

    get settings_notifications_path
    assert_select ".channel-group", "regroupées sur 30 min"

    patch settings_notification_channel_path(channel), params: { notification_channel: { group_minutes: "7" } }
    assert_response :unprocessable_content
    patch settings_notification_channel_path(channel), params: { notification_channel: { group_minutes: "0" } }
    assert_equal 0, channel.reload.group_minutes
    get settings_notifications_path
    assert_select ".channel-group", 0
  end
end
