# The detailed health of this installation, for a supervision tool (GET /up
# with the token of ELIO_HEALTH_TOKEN, see HealthController): can Elio reach
# its database, is a Solid Queue worker running, did the automations tick run
# lately. Each check says only ok / down / late / unknown, never an error
# message, a host name or the version of a dependency.
#
# "unknown" (another queue adapter, queue database absent) does not make the
# installation down: only what is known to be broken does.
class Installation::Health
  # RunDueAutomationsJob runs every minute (config/recurring.yml).
  AUTOMATIONS_LATE = 5.minutes

  def call
    checks = { database: { status: database }, jobs: { status: jobs }, automations: automations }
    status = checks.values.all? { |check| check[:status].in?(%w[ok unknown]) } ? "ok" : "down"
    { status: status, version: Elio::VERSION, checks: checks }
  end

  private

  def database
    ActiveRecord::Base.connection.select_value("SELECT 1")
    "ok"
  rescue ActiveRecord::ActiveRecordError, PG::Error
    "down"
  end

  def jobs
    case JobWorkers.running?
    when true then "ok"
    when false then "down"
    else "unknown"
    end
  end

  def automations
    last_run_at = JobWorkers.last_finished_at("RunDueAutomationsJob")
    return { status: "unknown" } if last_run_at == :unknown

    { status: last_run_at && last_run_at > AUTOMATIONS_LATE.ago ? "ok" : "late", last_run_at: last_run_at&.utc&.iso8601 }
  end
end
