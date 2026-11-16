# The last lines of the journal of a unit (lazy frame, loaded when the user
# opens it): a unit the last readings list as failed (Services tab), or the
# service a systemd timer starts (Scheduled tasks tab: the output of its last
# runs). Only such a unit, with a valid systemd name: nothing else is ever
# sent to the server. Operators and admins only: journal lines carry
# addresses, users, keys.
class ServerUnitJournalsController < ApplicationController
  require_permission :operate
  def show
    @server = Server.find(params[:server_id])
    @unit = params[:unit].to_s
    return head(:not_found) unless Inventory::UnitJournal.valid_name?(@unit) && readable_units.include?(@unit)

    @journal = Inventory::UnitJournal.call(@server, @unit)
  end

  private

  def readable_units
    Inventory::FailedUnits.new(@server).names + Inventory::Collectors::ScheduledTasks.timer_units(@server.inventory("scheduled_tasks"))
  end
end
