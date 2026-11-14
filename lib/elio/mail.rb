module Elio
  # SMTP settings of the outgoing emails, from environment variables:
  # SMTP_ADDRESS (enables sending), SMTP_PORT (587), SMTP_USERNAME,
  # SMTP_PASSWORD, SMTP_AUTHENTICATION (plain, only with a user name: a local
  # relay or Postfix without credentials must work too).
  module Mail
    module_function

    def enabled?(env = ENV) = env["SMTP_ADDRESS"].to_s.strip != ""

    def smtp_settings(env = ENV)
      user_name = env["SMTP_USERNAME"].presence
      {
        address: env["SMTP_ADDRESS"],
        port: Integer(env.fetch("SMTP_PORT", 587)),
        user_name: user_name,
        password: (env["SMTP_PASSWORD"].presence if user_name),
        authentication: (env.fetch("SMTP_AUTHENTICATION", "plain").to_sym if user_name),
        enable_starttls_auto: true,
        open_timeout: 5,
        read_timeout: 10
      }.compact
    end
  end
end
