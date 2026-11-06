require "test_helper"

class Inventory::HealthVersionTest < ActiveSupport::TestCase
  test "after an upgrade, the first tick computes the health of every server again, once" do
    AppSetting.current.update_columns(health_version: 0)
    servers(:web).update_columns(health_reasons: [ { "tone" => "warn", "text" => "Disque à 85 %" } ])

    RunDueAutomationsJob.perform_now
    assert_equal Inventory::HealthStatus::VERSION, AppSetting.current.reload.health_version
    assert servers(:web).reload.health_reasons.none? { |reason| reason.key?("text") }

    servers(:web).update_columns(health_reasons: [ { "tone" => "warn", "text" => "kept" } ])
    RunDueAutomationsJob.perform_now
    assert_equal [ { "tone" => "warn", "text" => "kept" } ], servers(:web).reload.health_reasons, "not again"
  end
end
