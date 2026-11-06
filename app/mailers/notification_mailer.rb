# Emails of the email notification channels.
class NotificationMailer < ApplicationMailer
  def activity(channel, activity)
    @activity = activity
    mail to: channel.recipient_list, subject: t("notification_mailer.activity_subject", label: activity.label, summary: activity.summary.truncate(120))
  end

  def batch(channel, group)
    @group = group
    mail to: channel.recipient_list, subject: t("notification_mailer.batch_subject", title: group.title)
  end

  def test(channel)
    @channel = channel
    mail to: channel.recipient_list, subject: t("notification_mailer.test_subject", channel_name: channel.name)
  end

  def digest(channel, digest)
    @digest = digest
    mail to: channel.recipient_list, subject: "[Elio] #{digest.title}"
  end
end
