require "test_helper"

class JobWorkersTest < ActiveSupport::TestCase
  test "unknown with another queue adapter (the test adapter)" do
    assert_nil JobWorkers.running?
    assert_equal :unknown, JobWorkers.last_finished_at("RunDueAutomationsJob")
  end
end
