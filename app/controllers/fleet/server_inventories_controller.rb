# Starts an inventory collection in the background, on one server
# (POST /servers/:server_id/inventory), the servers ticked in the list or
# every server (POST /servers/inventory), followed as a task on the "Tâches"
# page (see FleetRuns).
class ServerInventoriesController < ApplicationController
  include FleetRuns

  require_permission :operate

  def create
    start_run("inventory", run_servers, label: method(:label), notice: ->(task) { t("server_inventories_controller.started", label: task.label) }) do |item|
      Inventory::CollectJob.perform_later(item.server, task_item: item)
    end
  end

  private

  def label(servers)
    count = LocalizedText.part("count.servers", count: servers.size)
    case run_scope
    when :one then LocalizedText.part("server_inventories_controller.label_one", first_name: servers.first.name)
    when :selection then LocalizedText.part("server_inventories_controller.label_selection", t: count)
    else LocalizedText.part("server_inventories_controller.label_fleet", t: count)
    end
  end
end
