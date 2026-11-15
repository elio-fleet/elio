require "test_helper"

class RemindExpiringPublicKeysJobTest < ActiveJob::TestCase
  test "reminds once of the keyring keys close to their expiry date" do
    public_keys(:alice).update!(expires_on: 3.days.from_now.to_date)
    public_keys(:ci).update!(expires_on: 1.year.from_now.to_date)

    2.times { RemindExpiringPublicKeysJob.perform_now }

    assert_equal [ public_keys(:alice) ], Activity.of_kind(:public_key_expiring).map(&:public_key)
  end

  test "runs every hour in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each do |environment|
      assert_equal({ "class" => "RemindExpiringPublicKeysJob", "schedule" => "every hour at minute 7" }, recurring.dig(environment, "remind_expiring_public_keys"))
    end
  end
end
