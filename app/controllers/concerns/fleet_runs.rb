# Starts a run (inventory, keys scan) from the fleet: on one server
# (:server_id), the servers ticked in the list (server_ids[]) or the whole
# fleet. A server already waiting or running in a run of the same kind is
# left out: it would be read twice at the same time.
module FleetRuns
  extend ActiveSupport::Concern

  private

  def run_scope
    if params[:server_id] then :one
    elsif params.key?(:server_ids) then :selection
    else :fleet
    end
  end

  def run_servers
    case run_scope
    when :one then [ Server.find(params[:server_id]) ]
    when :selection then Server.where(id: Array(params[:server_ids])).order(:name).to_a
    else Server.order(:name).to_a
    end
  end

  # Creates the task on the servers that are free (`label` gets them) and
  # yields each item to enqueue its job, then shows the task; when every
  # server is busy, shows the run that already reads them.
  def start_run(kind, servers, label:, notice:, &enqueue)
    return redirect_back_or_to(servers_path, alert: t("fleet_runs.none_selected")) if servers.empty?

    busy_ids = BackgroundTask.busy_server_ids(kind).where(server_id: servers.map(&:id)).distinct.pluck(:server_id)
    free = servers.reject { |server| busy_ids.include?(server.id) }
    if free.empty?
      running = BackgroundTask.unfinished.where(kind: kind).joins(:items).where(background_task_items: { server_id: busy_ids }).order(:id).last
      return redirect_to task_path(running), notice: t("fleet_runs.already_running")
    end

    task = BackgroundTask.enqueue!(kind: kind, label: label.call(free), servers: free, &enqueue)
    message = notice.call(task)
    message = "#{message} #{t("fleet_runs.skipped", count: busy_ids.size)}" if busy_ids.any?
    redirect_to task_path(task), notice: message
  end
end
