# Holds an AdvisoryLock from a second PostgreSQL connection: in the tests,
# every thread shares the connection of the test transaction, on which the
# locks are reentrant.
module AdvisoryLockHelpers
  def with_lock_held_elsewhere(name)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(**{ dbname: config[:database], host: config[:host], port: config[:port], user: config[:username], password: config[:password] }.compact)
    key = AdvisoryLock.key(ActiveRecord::Base.connection, name)
    other.exec("SELECT pg_advisory_lock(#{key})")
    yield
  ensure
    other&.exec("SELECT pg_advisory_unlock(#{key})") if key
    other&.close
  end
end
