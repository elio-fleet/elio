require "test_helper"

class Installation::HealthTest < ActiveSupport::TestCase
  include StubHelpers

  test "unknown jobs and automations (another queue adapter) do not make it down" do
    health = Installation::Health.new.call

    assert_equal "ok", health[:status]
    assert_equal({ database: { status: "ok" }, jobs: { status: "unknown" }, automations: { status: "unknown" } }, health[:checks])
  end

  test "an unreachable database is down, without the error" do
    stub_method(ActiveRecord::Base, :connection, -> { raise ActiveRecord::ConnectionNotEstablished, "could not connect to db.internal:5432" }) do
      health = Installation::Health.new.call

      assert_equal [ "down", "down" ], [ health[:status], health.dig(:checks, :database, :status) ]
      assert_no_match "db.internal", health.to_json
    end
  end

  test "automations that never ran are late" do
    stub_method(JobWorkers, :last_finished_at, nil) do
      assert_equal({ status: "late", last_run_at: nil }, Installation::Health.new.call.dig(:checks, :automations))
    end
  end

  test "the last run of the automations is given" do
    travel_to Time.utc(2026, 11, 16, 10) do
      stub_method(JobWorkers, :last_finished_at, 2.minutes.ago) do
        assert_equal({ status: "ok", last_run_at: "2026-11-16T09:58:00Z" }, Installation::Health.new.call.dig(:checks, :automations))
      end
    end
  end
end
