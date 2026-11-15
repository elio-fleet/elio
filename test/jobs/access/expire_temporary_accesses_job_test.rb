require "test_helper"

class ExpireTemporaryAccessesJobTest < ActiveJob::TestCase
  include TemporaryAccessHelpers

  test "enqueues the expiry of every expired active access" do
    expired = create_temporary_access(expires_at: 1.minute.ago)
    create_temporary_access(public_key: public_keys(:alice), expires_at: 1.minute.from_now)
    create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 1.minute.ago).end!

    ExpireTemporaryAccessesJob.perform_now

    assert_enqueued_jobs 1, only: ExpireTemporaryAccessJob
    assert_enqueued_with(job: ExpireTemporaryAccessJob, args: [ expired ])
  end

  test "reminds once of the accesses about to end" do
    access = create_temporary_access(expires_at: 5.minutes.from_now)
    access.update_column(:created_at, 1.hour.ago)

    2.times { ExpireTemporaryAccessesJob.perform_now }

    assert_equal [ access.fingerprint ], Activity.of_kind(:key_expiring).map { |activity| activity.data["fingerprint"] }
    assert_no_enqueued_jobs only: ExpireTemporaryAccessJob
  end

  test "runs every minute in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each do |environment|
      assert_equal({ "class" => "ExpireTemporaryAccessesJob", "schedule" => "every minute" }, recurring.dig(environment, "expire_temporary_accesses"))
    end
  end
end
