require "test_helper"

class Installation::DoctorTest < ActiveSupport::TestCase
  include StubHelpers
  include TcpHelpers
  include VulnerabilityHelpers

  setup { Inventory::Snapshot.where(category: %w[os docker]).delete_all }

  test "a working installation: the report in the instance language, true" do
    io = StringIO.new
    assert Installation::Doctor.report(io, env: { "ELIO_HOST" => "elio.example.com" }, network: false)
    output = io.string
    assert_match "vérification de cette installation", output
    assert_match(/ok\s+Secrets\s+SECRET_KEY_BASE et les clés de chiffrement sont définis/, output)
    assert_match(/ok\s+Base #{ActiveRecord::Base.connection_db_config.database}\s+connectée, à jour/, output)
    assert_match "la clé SSH d'Elio se déchiffre", output
    assert_match "elio.example.com, HTTPS", output
    assert_match(/attention\s+Emails\s+SMTP_ADDRESS n'est pas défini/, output)
    assert_match "À faire : définir SMTP_ADDRESS", output
    assert_match "1 avertissement", output
  end

  test "a missing encryption key fails and says how to get one" do
    stub_method(ActiveRecord::Encryption.config, :primary_key, nil) do
      io = StringIO.new
      assert_not Installation::Doctor.report(io, env: {}, network: false)
      assert_match(/ÉCHEC\s+Secrets\s+Non définis : ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY/, io.string)
      assert_match "bin/elio-keys", io.string
      assert_match "1 problème à corriger", io.string
    end
  end

  test "databases: unreachable, missing, migrations to run" do
    host = ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :host, :port, :username, :password)
    # Over TCP, libpq tries GSSAPI first; on macOS that loads Kerberos, after
    # which the next fork of this test process (a spawned command) crashes.
    unreachable = config("queue", host.merge(host: "127.0.0.1", port: closed_port, database: "elio_queue", gssencmode: "disable"))
    missing = config("cache", host.merge(database: "elio_doctor_missing_#{SecureRandom.hex(4)}"))
    Dir.mktmpdir do |migrations|
      File.write(File.join(migrations, "20200101000001_missing_change.rb"), "class MissingChange < ActiveRecord::Migration[8.1]; end\n")
      pending = config("primary", ActiveRecord::Base.connection_db_config.configuration_hash.merge(migrations_paths: migrations))
      checks = I18n.with_locale(:en) { Installation::Doctor.new(env: {}, network: false, db_configs: [ pending, unreachable, missing ]).call }

      assert_equal [ :warning, "connected, 1 migration to run" ], checks.find { |check| check.subject == "Database #{ActiveRecord::Base.connection_db_config.database}" }.then { |check| [ check.status, check.message ] }
      assert_match "cannot connect", checks.find { |check| check.subject == "Database elio_queue" }.message
      assert_equal "does not exist", checks.find { |check| check.subject.start_with?("Database elio_doctor_missing") }.message
      assert_equal 2, checks.count(&:failure?)
    end
    assert_equal ActiveRecord::Base.connection_db_config.database, ActiveRecord::Base.connection.current_database, "the app's own connection is untouched"
  end

  test "encrypted data that the keys cannot read back fails" do
    key = Object.new.tap { |object| object.define_singleton_method(:private_key) { raise ActiveRecord::Encryption::Errors::Decryption } }
    stub_method(SshKey, :current, key) do
      check = run_checks.find { |each| each.subject == "Encrypted data" }
      assert_equal :failure, check.status
      assert_match "ACTIVE_RECORD_ENCRYPTION_*", check.fix
    end
    SshKey.delete_all
    assert_equal :warning, run_checks.find { |each| each.subject == "Encrypted data" }.status
  end

  test "address: plain HTTP and a missing ELIO_HOST are warnings" do
    assert_equal "ELIO_FORCE_SSL=false: plain HTTP, passwords travel unencrypted", subject_check("Address", env: { "ELIO_FORCE_SSL" => "false", "ELIO_HOST" => "x" }).message
    assert_match "ELIO_HOST is not set", subject_check("Address", env: {}).message
  end

  test "emails: the SMTP server is tried without sending anything, its refusal fails" do
    with_smtp_server do |port, commands|
      check = subject_check("Emails", env: { "SMTP_ADDRESS" => "127.0.0.1", "SMTP_PORT" => port.to_s }, network: true)
      assert_equal [ :ok, "127.0.0.1:#{port} accepts the connection" ], [ check.status, check.message ]
      check = subject_check("Emails", env: { "SMTP_ADDRESS" => "127.0.0.1", "SMTP_PORT" => port.to_s, "SMTP_USERNAME" => "elio", "SMTP_PASSWORD" => "wrong" }, network: true)
      assert_equal :failure, check.status
      assert_match "535", check.message
      assert_not commands.any? { |command| command.start_with?("MAIL", "RCPT", "DATA") }
    end
    assert_equal :failure, subject_check("Emails", env: { "SMTP_ADDRESS" => "127.0.0.1", "SMTP_PORT" => closed_port.to_s }, network: true).status
    assert_equal :ok, subject_check("Emails", env: { "SMTP_ADDRESS" => "127.0.0.1" }).status, "not tried offline"
  end

  test "feeds: only those the fleet needs, their last update and whether they answer" do
    assert_equal "no server inventoried yet, no feed needed", subject_check("Vulnerability feeds").message

    record_os(servers(:web))
    VulnerabilityFeed.for("debian").update!(refreshed_at: Time.zone.local(2026, 11, 2, 8, 0))
    asked = []
    stub_method(Vulnerabilities::Download, :check, ->(url) { asked << url; nil }) do
      assert_equal [ :ok, "updated on Nov 02 08:00" ], subject_check("Feed Debian Security Tracker", network: true).then { |check| [ check.status, check.message ] }
    end
    assert_equal [ Vulnerabilities::DebianTracker::URL ], asked.uniq

    stub_method(Vulnerabilities::Download, :check, ->(_url) { raise Vulnerabilities::Error, "Cannot download: timeout" }) do
      check = subject_check("Feed Debian Security Tracker", network: true)
      assert_equal :warning, check.status
      assert_match "security-tracker.debian.org does not answer: Cannot download: timeout", check.message
    end
  end

  test "bin/elio-doctor --help explains itself without starting the application" do
    output = `#{RbConfig.ruby} #{Rails.root.join("bin/elio-doctor")} --help`
    assert_match "bin/elio-doctor --offline", output
  end

  test "bin/elio-doctor says that SECRET_KEY_BASE is missing in production, where Elio would not even start" do
    skip "this checkout has a config/master.key" if Rails.root.join("config/master.key").exist?

    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => nil, "RAILS_MASTER_KEY" => nil }
    output = IO.popen(env, [ RbConfig.ruby, Rails.root.join("bin/elio-doctor").to_s ], &:read)
    assert_not $?.success?
    assert_match "SECRET_KEY_BASE is not set", output
    assert_match "bin/elio-keys", output
  end

  private

  def config(name, hash) = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", name, hash)

  def run_checks(env: {}, network: false) = I18n.with_locale(:en) { Installation::Doctor.new(env: env, network: network).call }

  def subject_check(subject, **options) = run_checks(**options).find { |check| check.subject == subject }

  # A minimal SMTP server: accepts the connection, refuses any authentication.
  def with_smtp_server
    server = TCPServer.new("127.0.0.1", 0)
    commands = []
    thread = Thread.new do
      loop do
        socket = server.accept
        socket.write("220 fake ESMTP\r\n")
        while (line = socket.gets)
          commands << line.strip
          case line
          when /\AEHLO/ then socket.write("250-fake\r\n250 AUTH PLAIN LOGIN\r\n")
          when /\AAUTH/ then socket.write("535 5.7.8 Authentication failed\r\n")
          when /\AQUIT/ then socket.write("221 bye\r\n") && break
          else socket.write("502 not here\r\n")
          end
        end
        socket.close
      rescue IOError, Errno::ECONNRESET
        next
      end
    end
    yield server.addr[1], commands
  ensure
    thread&.kill
    server&.close
  end
end
