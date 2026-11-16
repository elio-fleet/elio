require "test_helper"

class ElioEnvTest < ActiveSupport::TestCase
  test "a whole number, its default when not set" do
    assert_equal 4, Elio::Env.integer("ELIO_PARALLEL_LIMIT", {})
    assert_equal 4, Elio::Env.integer("ELIO_PARALLEL_LIMIT", "ELIO_PARALLEL_LIMIT" => " ")
    assert_equal 8, Elio::Env.integer("ELIO_PARALLEL_LIMIT", "ELIO_PARALLEL_LIMIT" => " 8 ")
    assert_equal 0, Elio::Env.integer("ELIO_ACTIVITY_RETENTION_DAYS", "ELIO_ACTIVITY_RETENTION_DAYS" => "0")
    assert_equal 25, Elio::Env.integer("SMTP_PORT", "SMTP_PORT" => "25")
  end

  test "a value that cannot be read stops with a message naming the variable" do
    error = assert_raises(Elio::Env::Invalid) { Elio::Env.integer("ELIO_PARALLEL_LIMIT", "ELIO_PARALLEL_LIMIT" => "four") }
    assert_equal 'ELIO_PARALLEL_LIMIT="four" is not valid: expected a whole number, 1 or more (4 when it is not set)', error.message
    assert_raises(Elio::Env::Invalid) { Elio::Env.integer("ELIO_PARALLEL_LIMIT", "ELIO_PARALLEL_LIMIT" => "0") }
    assert_raises(Elio::Env::Invalid) { Elio::Env.integer("ELIO_ACTIVITY_RETENTION_DAYS", "ELIO_ACTIVITY_RETENTION_DAYS" => "1y") }
    assert_raises(Elio::Env::Invalid) { Elio::Env.integer("SMTP_PORT", "SMTP_PORT" => "2.5") }
  end

  test "validate! checks every variable, and runs when Elio starts" do
    assert_nothing_raised { Elio::Env.validate!({}) }
    assert_match "SMTP_PORT", assert_raises(Elio::Env::Invalid) { Elio::Env.validate!("SMTP_PORT" => "smtp") }.message
    assert_match "Elio::Env.validate!", Rails.root.join("config/initializers/env.rb").read
  end
end
