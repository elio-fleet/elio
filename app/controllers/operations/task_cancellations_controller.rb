# Calls off the servers still waiting in a run (POST /journal/runs/:task_id/cancel):
# the servers already being read finish. Same permission as starting the run
# again (BackgroundTask#rerun_permission).
class TaskCancellationsController < ApplicationController
  require_permission :operate

  def create
    task = BackgroundTask.find(params[:task_id])
    authorize!(task.rerun_permission)
    return redirect_to(task_path(task), alert: t("task_cancellations_controller.not_cancellable")) unless task.cancellable?

    task.cancel!
    redirect_to task_path(task), notice: t("task_cancellations_controller.cancelled")
  end
end
