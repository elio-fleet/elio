# Groups of servers, managed from the Servers page. A group's own page is the
# server list filtered on it (servers_path(group:)).
class ServerGroupsController < ApplicationController
  require_permission :operate, only: %i[new create edit update destroy]

  before_action :set_group, only: %i[edit update destroy]

  def index
    @groups = ServerGroup.order(:name).includes(:servers)
  end

  def new
    @group = ServerGroup.new(server_ids: Array(params[:server_ids]))
  end

  def create
    @group = ServerGroup.new(group_params)

    if @group.save
      Activity.record!(:server_group_created, group_name: @group.name, servers: @group.servers.size)
      redirect_to servers_path(group: @group.id), notice: t("server_groups_controller.created", group_name: @group.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params)
      redirect_to servers_path(group: @group.id), notice: t("server_groups_controller.updated", group_name: @group.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy!
    Activity.record!(:server_group_deleted, group_name: @group.name)
    redirect_to server_groups_path, notice: t("server_groups_controller.deleted", group_name: @group.name), status: :see_other
  end

  private

  def set_group
    @group = ServerGroup.find(params[:id])
  end

  def group_params
    params.expect(server_group: [ :name, :color, :expected_ports, server_ids: [], ssh_source_ids: [] ])
  end
end
