# Dry run of a key rotation on one server (Keys::RotationCheck), reported to
# its BackgroundTask item: nothing is written on the server.
class CheckKeyRotationJob < ApplicationJob
  include TracksTaskItem

  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(server, task_item: nil)
    tracking(task_item) do
      check = Keys::RotationCheck.call(server)
      task_item&.finish!(check.success? ? :succeeded : :failed, check.message)
    end
  end
end
