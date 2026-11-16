require "test_helper"

class PurgeActivitiesJobTest < ActiveJob::TestCase
  test "forgets the activities older than the retention, 365 days by default" do
    old = travel_to(366.days.ago) { Activity.record!(:server_created, server: servers(:web)) }
    recent = travel_to(300.days.ago) { Activity.record!(:server_created, server: servers(:web)) }

    PurgeActivitiesJob.perform_now

    assert_not Activity.exists?(old.id)
    assert Activity.exists?(recent.id)
  end

  test "the retention can be changed or disabled" do
    old = travel_to(40.days.ago) { Activity.record!(:server_created, server: servers(:web)) }

    ENV["ELIO_ACTIVITY_RETENTION_DAYS"] = "0"
    PurgeActivitiesJob.perform_now
    assert Activity.exists?(old.id)

    ENV["ELIO_ACTIVITY_RETENTION_DAYS"] = "30"
    PurgeActivitiesJob.perform_now
    assert_not Activity.exists?(old.id)

    # Once read as 0 (keep everything) without a word.
    ENV["ELIO_ACTIVITY_RETENTION_DAYS"] = "1y"
    assert_raises(Elio::Env::Invalid) { PurgeActivitiesJob.perform_now }
  ensure
    ENV.delete("ELIO_ACTIVITY_RETENTION_DAYS")
  end

  test "runs every day in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each { |environment| assert_equal "PurgeActivitiesJob", recurring.dig(environment, "purge_activities", "class") }
  end
end
