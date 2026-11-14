class ApplicationJob < ActiveJob::Base
  # Notification jobs (queue "notifications") pass before the jobs already
  # waiting, such as the inventories of a whole fleet: Solid Queue takes the
  # lowest priority first (0 by default).
  NOTIFICATIONS_PRIORITY = -10

  # Results and errors written by the jobs (tasks, last errors) are in the
  # instance's language, whoever started them. Notifications switch to their
  # channel's language.
  around_perform { |_job, block| I18n.with_locale(AppSetting.current.default_locale, &block) }

  # The task (or task item) a job runs remembers the job's id, so that a task
  # whose job no longer exists can be told apart (StaleTasks).
  after_enqueue do |job|
    job.arguments.flat_map { |argument| argument.is_a?(Hash) ? argument.values : [ argument ] }
       .select { |argument| argument.is_a?(BackgroundTask) || argument.is_a?(BackgroundTaskItem) }
       .each { |record| record.update_column(:active_job_id, job.job_id) }
  end
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
