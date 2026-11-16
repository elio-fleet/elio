# What this installation read from its environment variables, for Settings →
# General: by group, the check of Installation::Doctor that covers it (without
# network: nothing is tried from a page) and the value in use of each
# variable. A secret is never shown, only whether it is set; a mirror URL is
# shown without its credentials or query.
class Installation::Configuration
  # default: the value used when the variable is not set (a Symbol: a key of
  # settings.show.configuration.defaults).
  Variable = Data.define(:name, :value, :secret, :default) do
    def set? = value.present?
  end
  Group = Data.define(:key, :check, :variables)

  FEEDS = %w[ELIO_DEBIAN_TRACKER_URL ELIO_UBUNTU_OSV_URL ELIO_NVD_FEED_URL ELIO_EPSS_URL ELIO_KEV_URL].freeze

  def initialize(env: ENV)
    @env = env
  end

  def groups
    checks = Installation::Doctor.new(env: @env, network: false).environment_checks
    [
      Group.new(:secrets, checks[:secrets], [ secret("ELIO_DATABASE_PASSWORD"), secret("ELIO_SETUP_TOKEN") ]),
      Group.new(:address, checks[:address], [ plain("ELIO_HOST"), plain("ELIO_FORCE_SSL", "true") ]),
      Group.new(:mail, checks[:mail], [ plain("SMTP_ADDRESS"), integer("SMTP_PORT"), secret("SMTP_USERNAME"), secret("SMTP_PASSWORD"),
                                        plain("SMTP_AUTHENTICATION", "plain"), plain("ELIO_MAIL_FROM", "elio@localhost") ]),
      Group.new(:limits, nil, [ integer("ELIO_PARALLEL_LIMIT"), integer("ELIO_ACTIVITY_RETENTION_DAYS") ]),
      Group.new(:feeds, nil, FEEDS.map { |name| Variable.new(name, without_credentials(@env[name]), false, :official_feed) })
    ]
  end

  private

  def plain(name, default = nil) = Variable.new(name, @env[name].presence, false, default)

  def secret(name) = Variable.new(name, @env[name].presence, true, nil)

  def integer(name) = plain(name, Elio::Env::INTEGERS.fetch(name).first.to_s)

  # https://user:token@mirror.lan/path?key=… → https://mirror.lan/path
  def without_credentials(url)
    url.presence&.sub(%r{//[^/@]*@}, "//")&.sub(/[?#].*\z/m, "")
  end
end
