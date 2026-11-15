# Packages of a server (lazy frame of the server page), searchable and
# filterable: ?q=, ?manager=, ?updates=1 (only the upgradable ones),
# ?outside=1 (only those from backports, third-party repositories or none).
class ServerPackagesController < ApplicationController
  PER_PAGE = 100

  def index
    @server = Server.find(params[:server_id])
    @snapshot = @server.inventory("packages")
    @q = params[:q].to_s.strip.first(100)
    @manager = params[:manager].presence_in(Inventory::Package::MANAGERS)
    @updates = params[:updates] == "1"
    @outside = params[:outside] == "1"

    packages = @server.packages.order(:name, :arch)
    packages = packages.search(@q) if @q.present?
    packages = packages.where(manager: @manager) if @manager
    packages = packages.outside_distribution if @outside
    packages = packages.upgradable.reorder(security: :desc, name: :asc) if @updates
    @pager = paginate(packages, per_page: PER_PAGE)
    @packages = @pager.records
  end
end
