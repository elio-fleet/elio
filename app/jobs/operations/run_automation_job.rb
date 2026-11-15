# Runs an automation, followed by its BackgroundTask when there is one (the
# quiet automations, every 15 minutes, have none).
class RunAutomationJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(automation, task = nil)
    task&.start!
    result = automation.run!(task: task)
    task&.refresh!(result: LocalizedText.render(result)) # plain text: searched in the Journal
  rescue StandardError => e
    task&.fail!(I18n.t("run_automation_job.internal_error", class: e.class))
    raise
  end
end
