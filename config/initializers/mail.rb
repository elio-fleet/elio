# Outgoing emails (password reset, invitations), configured by environment
# variables (see Elio::Mail): SMTP_ADDRESS (enables sending), SMTP_PORT (587),
# SMTP_USERNAME, SMTP_PASSWORD, SMTP_AUTHENTICATION (plain, only with a user
# name), ELIO_HOST (host of the links in the emails) and ELIO_MAIL_FROM
# (sender). Without SMTP_ADDRESS, nothing is sent and the "forgot password"
# link is hidden.

Rails.application.configure do
  config.x.mail_enabled = Rails.env.test? || Elio::Mail.enabled?

  if Elio::Mail.enabled?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = Elio::Mail.smtp_settings
  end

  if ENV["ELIO_HOST"].present?
    config.action_mailer.default_url_options = { host: ENV["ELIO_HOST"], protocol: Elio::Mail.url_protocol }
  end
end
