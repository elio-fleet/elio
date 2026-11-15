require "test_helper"

class Installation::ConfigurationTest < ActiveSupport::TestCase
  ENV_VALUES = {
    "ELIO_HOST" => "elio.example.com", "SMTP_ADDRESS" => "smtp.example.com", "SMTP_USERNAME" => "elio@example.com",
    "SMTP_PASSWORD" => "smtp-secret", "ELIO_SETUP_TOKEN" => "setup-secret", "ELIO_PARALLEL_LIMIT" => "8",
    "ELIO_DEBIAN_TRACKER_URL" => "https://mirror:mirror-secret@mirror.lan/debian/json?key=query-secret"
  }.freeze

  test "the value in use of each variable, by group, with the check of the doctor (no network)" do
    groups = Installation::Configuration.new(env: ENV_VALUES).groups.index_by(&:key)

    assert_equal %i[secrets address mail limits feeds], groups.keys
    assert_equal :ok, groups[:address].check.status
    assert_match "elio.example.com", groups[:address].check.message
    assert_equal "smtp.example.com:587 configuré (non essayé)", groups[:mail].check.message
    assert_nil groups[:limits].check

    host, force_ssl = groups[:address].variables
    assert_equal [ "ELIO_HOST", "elio.example.com", nil ], [ host.name, host.value, host.default ]
    assert_equal [ nil, "true" ], [ force_ssl.value, force_ssl.default ]
    assert_equal [ [ "ELIO_PARALLEL_LIMIT", "8", "4" ], [ "ELIO_ACTIVITY_RETENTION_DAYS", nil, "365" ] ],
                 groups[:limits].variables.map { |variable| [ variable.name, variable.value, variable.default ] }
  end

  test "without SMTP_ADDRESS, the emails group warns" do
    assert_equal :warning, Installation::Configuration.new(env: {}).groups.find { |group| group.key == :mail }.check.status
  end

  test "secrets are only set or not set, a mirror is shown without its credentials" do
    groups = Installation::Configuration.new(env: ENV_VALUES).groups.index_by(&:key)

    secrets = groups.values.flat_map(&:variables).select(&:secret)
    assert_equal %w[ELIO_DATABASE_PASSWORD ELIO_SETUP_TOKEN SMTP_USERNAME SMTP_PASSWORD], secrets.map(&:name)
    assert_equal [ false, true, true, true ], secrets.map(&:set?)

    debian, ubuntu = groups[:feeds].variables
    assert_equal "https://mirror.lan/debian/json", debian.value
    assert_equal [ nil, :official_feed ], [ ubuntu.value, ubuntu.default ]
  end
end
