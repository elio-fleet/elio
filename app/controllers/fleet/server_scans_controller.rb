# Reads the keys of every server, or of the servers ticked in the list, in
# the background, followed as a task on the "Tâches" page (see FleetRuns).
class ServerScansController < ApplicationController
  include FleetRuns

  require_permission :operate

  def create
    label = ->(servers) { LocalizedText.part("server_scans_controller.label", t: LocalizedText.part("count.servers", count: servers.size)) }
    start_run("keys_scan", run_servers, label: label, notice: ->(_task) { t("server_scans_controller.started") }) do |item|
      ScanServerJob.perform_later(item.server, task_item: item)
    end
  end
end
