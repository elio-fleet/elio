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
      refresh_health(@group.server_ids) if @group.expected_ports || @group.health_thresholds.any? || @group.vulnerability_alert_severity
      Activity.record!(:server_group_created, group_name: @group.name, servers: @group.servers.size)
      redirect_to servers_path(group: @group.id), notice: t("server_groups_controller.created", group_name: @group.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    server_ids = @group.server_ids
    if @group.update(group_params)
      # Its expected ports and thresholds apply to its servers, old and new.
      if @group.saved_changes.keys.intersect?(%w[expected_ports health_thresholds vulnerability_alert_severity]) || server_ids.sort != @group.server_ids.sort
        refresh_health(server_ids | @group.server_ids)
      end
      redirect_to servers_path(group: @group.id), notice: t("server_groups_controller.updated", group_name: @group.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    server_ids = @group.server_ids
    @group.destroy!
    refresh_health(server_ids)
    Activity.record!(:server_group_deleted, group_name: @group.name)
    redirect_to server_groups_path, notice: t("server_groups_controller.deleted", group_name: @group.name), status: :see_other
  end

  private

  def set_group
    @group = ServerGroup.find(params[:id])
  end

  def group_params
    params.expect(server_group: [ :name, :color, :expected_ports, :vulnerability_alert_severity, server_ids: [], ssh_source_ids: [], health_thresholds: Inventory::HealthThresholds::KEYS ])
  end

  def refresh_health(server_ids)
    Server.where(id: server_ids).where.not(health_status: nil).includes(:server_groups).find_each(&:refresh_health!)
  end
end
