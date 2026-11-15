# Starts a finished run again (POST /journal/runs/:task_id/rerun): on all
# its servers, or only those that failed (only_failed=1). Operators for the
# inventories and key scans, admins for the automations and the key rotation
# checks (see BackgroundTask#rerun_permission).
class TaskRerunsController < ApplicationController
  require_permission :operate

  def create
    task = BackgroundTask.find(params[:task_id])
    authorize!(task.rerun_permission)
    only_failed = params[:only_failed] == "1"
    return redirect_to(task_path(task), alert: t("task_reruns_controller.not_rerunnable")) unless only_failed ? task.failures_rerunnable? : task.rerunnable?

    rerun = task.rerun!(user: current_user, only_failed: only_failed)
    return redirect_to(task_path(task), alert: t("task_reruns_controller.servers_busy")) unless rerun

    redirect_to task_path(rerun), notice: t("task_reruns_controller.started", label: rerun.label)
  end
end
