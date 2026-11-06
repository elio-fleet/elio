# Runs every minute (config/recurring.yml): starts the enabled automations
# whose interval has elapsed. last_run_at is set before enqueuing so a slow
# run is not started twice by the next tick. The automations are created on
# the first tick (Automation.all_kinds), so the ones enabled by default run on
# a new installation without visiting the settings. After an upgrade, it
# first computes the health of the servers again if its rules changed
# (Inventory::HealthStatus.refresh_outdated!).
class RunDueAutomationsJob < ApplicationJob
  queue_as :default

  def perform
    Inventory::HealthStatus.refresh_outdated!
    Automation.all_kinds.select(&:due?).each do |automation|
      automation.update!(last_run_at: Time.current)
      automation.enqueue!
    end
  end
end
