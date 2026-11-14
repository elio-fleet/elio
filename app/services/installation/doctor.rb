require "net/smtp"

# Checks an installation the way an administrator would before asking for
# help: secrets, databases, encrypted data, address, emails, vulnerability
# feeds; each problem comes with what to change. Run by bin/elio-doctor (in
# the container: `docker compose exec elio bin/elio-doctor`), in the language
# of the instance.
#
# It writes nothing and only reaches what Elio already reaches: PostgreSQL,
# the SMTP server (a connection and its authentication, no email sent), and a
# HEAD request to each vulnerability feed of the fleet. `network: false`
# skips the SMTP server and the feeds.
class Installation::Doctor
  Check = Data.define(:status, :subject, :message, :fix) do
    def failure? = status == :failure
    def warning? = status == :warning
  end

  # A pool of its own for each database, apart from the application's.
  class Probe < ActiveRecord::Base
    self.abstract_class = true
  end

  SMTP_ERRORS = [ Net::SMTPError, *Vulnerabilities::Download::NETWORK_ERRORS ].freeze

  def initialize(env: ENV, network: true, db_configs: ActiveRecord::Base.configurations.configs_for(env_name: Rails.env))
    @env = env
    @network = network
    @db_configs = db_configs
  end

  # Prints the checks; false when one of them failed.
  def self.report(io = $stdout, **options)
    doctor = new(**options)
    I18n.with_locale(doctor.locale) do
      checks = doctor.call
      io.puts I18n.t("installation_doctor.title", version: Elio::VERSION), ""
      width = checks.map { |check| check.subject.size }.max
      checks.each do |check|
        io.puts format("  %-9s %-#{width}s  %s", I18n.t("installation_doctor.statuses.#{check.status}"), check.subject, check.message)
        io.puts format("  %-9s %-#{width}s  %s", "", "", I18n.t("installation_doctor.fix", fix: check.fix)) if check.fix && !check.status.equal?(:ok)
      end
      io.puts "", summary(checks)
      checks.none?(&:failure?)
    end
  end

  def self.summary(checks)
    failures = checks.count(&:failure?)
    warnings = checks.count(&:warning?)
    return I18n.t("installation_doctor.summary.ok") if failures.zero? && warnings.zero?

    [ (I18n.t("installation_doctor.summary.failures", count: failures) if failures.positive?),
      (I18n.t("installation_doctor.summary.warnings", count: warnings) if warnings.positive?) ].compact.join(" · ")
  end

  def call
    checks = [ secrets ]
    databases = @db_configs.map { |db_config| database(db_config) }
    checks.concat(databases)
    checks.concat([ encrypted_data, *feeds, scores ].compact) if databases.first&.status == :ok
    checks << address << mail
  end

  # The language of the instance (Settings → General), else the default one.
  def locale
    Elio::Locales.find(AppSetting.first&.default_locale) || I18n.default_locale
  rescue ActiveRecord::ActiveRecordError, PG::Error
    I18n.default_locale
  end

  private

  def secrets
    missing = []
    begin
      missing << "SECRET_KEY_BASE" if Rails.application.secret_key_base.blank?
    rescue ArgumentError
      missing << "SECRET_KEY_BASE"
    end
    missing.concat(Elio::Secrets::ENCRYPTION.filter_map { |key, variable| variable if ActiveRecord::Encryption.config.public_send(key).blank? })
    return check(:ok, "secrets") if missing.empty?

    check(:failure, "secrets", :missing, fix: :fix, variables: missing.join(", "))
  end

  def database(db_config)
    subject = I18n.t("installation_doctor.database.subject", name: db_config.database)
    Probe.establish_connection(db_config)
    context = Probe.connection_pool.migration_context
    pending = (context.migrations.map(&:version) - context.get_all_versions).size
    return Check.new(:ok, subject, t("database.ok"), nil) if pending.zero?

    Check.new(:warning, subject, t("database.pending", count: pending), t("database.pending_fix"))
  rescue ActiveRecord::NoDatabaseError
    Check.new(:failure, subject, t("database.missing"), t("database.missing_fix"))
  rescue ActiveRecord::ConnectionNotEstablished, PG::Error => e
    Check.new(:failure, subject, t("database.unreachable", error: e.message.lines.first.to_s.strip.truncate(150)), t("database.unreachable_fix"))
  ensure
    Probe.remove_connection
  end

  def encrypted_data
    key = SshKey.current
    return check(:warning, "encrypted_data", :no_key, fix: :no_key_fix) if key.nil?

    key.private_key
    check(:ok, "encrypted_data")
  rescue ActiveRecord::Encryption::Errors::Decryption
    check(:failure, "encrypted_data", :unreadable, fix: :unreadable_fix)
  end

  # One line per feed the fleet needs: its last update, and whether it answers.
  def feeds
    releases = Vulnerabilities.releases.select { |_, list| list.any? }
    return [ Check.new(:ok, t("feeds.none_subject"), t("feeds.no_server"), nil) ] if releases.empty?

    releases.map do |source, list|
      feed = VulnerabilityFeed.for(source)
      subject = t("feeds.subject", label: feed.label)
      unreachable = @network && list.map { |release| Vulnerabilities::Update::READERS.fetch(source).url(release) }.uniq.filter_map { |url| feed_error(url) }.first
      if unreachable
        Check.new(:warning, subject, t("feeds.unreachable", host: unreachable.first, error: unreachable.last), t("feeds.unreachable_fix", host: unreachable.first))
      elsif feed.failed?
        Check.new(:warning, subject, t("feeds.failed", date: I18n.l(feed.failed_at, format: :short), error: feed.last_error.to_s.truncate(150)), t("feeds.failed_fix"))
      elsif feed.refreshed_at.nil?
        Check.new(:warning, subject, t("feeds.never"), t("feeds.never_fix"))
      else
        Check.new(:ok, subject, t("feeds.ok", date: I18n.l(feed.refreshed_at, format: :short)), nil)
      end
    end
  end

  # [host, error] when the feed does not answer.
  def feed_error(url)
    Vulnerabilities::Download.check(url)
    nil
  rescue Vulnerabilities::Error => e
    [ URI(url).host, e.message ]
  end

  def scores
    failed = ScoreProvider.active.where.not(last_error: [ nil, "" ]).order(:position, :id)
    return check(:ok, "scores") if failed.none?

    check(:warning, "scores", :failed, fix: :failed_fix, names: failed.map(&:name).join(", "), error: failed.first.last_error.truncate(150))
  end

  def address
    if @env["ELIO_FORCE_SSL"] == "false"
      check(:warning, "address", :plain_http, fix: :plain_http_fix)
    elsif @env["ELIO_HOST"].blank?
      check(:warning, "address", :no_host, fix: :no_host_fix)
    else
      check(:ok, "address", :ok, host: @env["ELIO_HOST"])
    end
  end

  def mail
    return check(:warning, "mail", :disabled, fix: :disabled_fix) unless Elio::Mail.enabled?(@env)

    settings = Elio::Mail.smtp_settings(@env)
    server = "#{settings[:address]}:#{settings[:port]}"
    return check(:ok, "mail", :not_tried, server: server) unless @network

    try_smtp(settings)
    check(:ok, "mail", settings[:user_name] ? :authenticated : :ok, server: server)
  rescue *SMTP_ERRORS => e
    check(:failure, "mail", :failed, fix: :failed_fix, server: server, error: e.message.strip.truncate(150))
  end

  # Connects as Action Mailer would (STARTTLS when offered, authentication
  # with a user name), then leaves without sending anything.
  def try_smtp(settings)
    smtp = Net::SMTP.new(settings[:address], settings[:port])
    smtp.open_timeout = settings[:open_timeout]
    smtp.read_timeout = settings[:read_timeout]
    smtp.enable_starttls_auto if settings[:enable_starttls_auto]
    smtp.start(helo: @env["ELIO_HOST"].presence || "localhost", user: settings[:user_name], secret: settings[:password], authtype: settings[:authentication]) { }
  end

  def check(status, area, message = :ok, fix: nil, **params)
    Check.new(status, t("#{area}.subject"), t("#{area}.#{message}", **params), (t("#{area}.#{fix}", **params) if fix))
  end

  def t(key, **params) = I18n.t("installation_doctor.#{key}", **params)
end
