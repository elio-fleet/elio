module SlackHelpers
  WEBHOOK = "https://hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXXXXXXXXXX".freeze

  # Sends right away unless `group_minutes` is given (grouping: NotificationBatchesTest).
  def create_channel(name: "#ops", activity_kinds: %w[unknown_key_detected ssh_access_lost], group_minutes: 0, **attributes)
    NotificationChannel.create!(name: name, webhook_url: WEBHOOK, activity_kinds: activity_kinds, group_minutes: group_minutes, **attributes)
  end
end
