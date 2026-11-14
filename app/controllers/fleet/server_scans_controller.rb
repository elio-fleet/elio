# Reads the keys of every server in the background, followed as a task on
# the "Tâches" page.
class ServerScansController < ApplicationController
  require_permission :operate

  def create
    servers = Server.order(:name).to_a
    task = BackgroundTask.enqueue!(kind: "keys_scan", label: LocalizedText.part("server_scans_controller.label", t: LocalizedText.part("count.servers", count: servers.size)), servers: servers) do |item|
      ScanServerJob.perform_later(item.server, task_item: item)
    end

    redirect_to task_path(task), notice: t("server_scans_controller.started")
  end
end
