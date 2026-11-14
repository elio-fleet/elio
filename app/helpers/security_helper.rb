module SecurityHelper
  # Cookie set by the "Hide" button of the plain HTTP notice (dismiss_controller.js).
  PLAIN_HTTP_DISMISSED = "elio_plain_http_notice"
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze

  # Whether this request reached Elio over plain HTTP in production. Never
  # when HTTPS is forced (ELIO_FORCE_SSL: every request is then HTTPS), nor
  # behind a proxy that says it is (X-Forwarded-Proto), nor on localhost (a
  # trial).
  def self.plain_http?(request)
    Rails.env.production? && !request.ssl? && LOOPBACK_HOSTS.exclude?(request.host)
  end

  # Whether to tell an administrator about it; once hidden, never again in
  # that browser (a LAN installation on purpose).
  def plain_http_notice?
    SecurityHelper.plain_http?(request) && cookies[PLAIN_HTTP_DISMISSED].blank? && can?(:administer)
  end
end
