# For the jobs that work on one item of a BackgroundTask: the item is running
# during the job, and failed if the job crashes (the error is re-raised). An
# item already finished (its run was cancelled while it waited) is skipped.
module TracksTaskItem
  extend ActiveSupport::Concern

  private

  def tracking(item)
    return if item&.finished?

    item&.start!
    yield
  rescue StandardError => e
    item&.finish!(:failed, "Erreur interne (#{e.class})") unless item&.reload&.finished?
    raise
  end
end
