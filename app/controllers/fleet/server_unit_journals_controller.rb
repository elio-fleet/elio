# The last lines of the journal of a failed unit (lazy frame of the Services
# tab, loaded when the user opens it). Only a unit the last readings list as
# failed, with a valid systemd name: nothing else is ever sent to the server.
class ServerUnitJournalsController < ApplicationController
  def show
    @server = Server.find(params[:server_id])
    @unit = params[:unit].to_s
    return head(:not_found) unless Inventory::UnitJournal.valid_name?(@unit) && Inventory::FailedUnits.new(@server).names.include?(@unit)

    @journal = Inventory::UnitJournal.call(@server, @unit)
  end
end
