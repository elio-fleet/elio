require "net/smtp"

# Sends notifications to the channel's email recipients (needs SMTP, see
# config/initializers/mail.rb). Sent right away from DeliverNotificationJob.
class Notifications::Email
  def self.deliver(channel, activity) = send_mail { NotificationMailer.activity(channel, activity) }

  def self.deliver_test(channel) = send_mail { NotificationMailer.test(channel) }

  def self.deliver_batch(channel, group) = send_mail { NotificationMailer.batch(channel, group) }

  def self.deliver_digest(channel, digest) = send_mail { NotificationMailer.digest(channel, digest) }

  def self.send_mail
    raise Notifications::DeliveryError, I18n.t("notifications.email.not_configured") unless Rails.configuration.x.mail_enabled

    yield.deliver_now
  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError => e
    raise Notifications::DeliveryError, I18n.t("notifications.email.failed", class: e.class, message: e.message)
  end
end
