class ServersController < ApplicationController
  PER_PAGE = 100
  VIEWS = %w[list grid].freeze
  # Grid: the problems first.
  STATE_ORDER = { "crit" => 0, "off" => 0, "warn" => 1, "unknown" => 2, "ok" => 3 }.freeze
  HISTORY_PER_PAGE = 30

  require_permission :operate, only: %i[new create edit update destroy]

  before_action :set_server, only: %i[show edit update destroy]

  # State filter on the Docker state (servers.docker_status) instead of the health.
  DOCKER_FILTERS = { "docker_warn" => "warn", "docker_crit" => "crit" }.freeze

  def index
    @groups = ServerGroup.order(:name)
    @group = @groups.find { |group| group.id.to_s == params[:group].to_s } if params[:group].present?
    @os_names = Server.where.not(os_name: nil).distinct.order(:os_name).pluck(:os_name)
    @os = params[:os].presence_in(@os_names)
    @state = params[:state].presence_in(Server::HEALTH_STATES + %w[off] + DOCKER_FILTERS.keys)
    @summary = FleetSummary.new(Server.includes(:inventory_snapshots))
    servers = (@group ? Server.in_group(@group) : Server.all).order(:name).includes(:server_groups, :inventory_snapshots)
    servers = servers.where(os_name: @os) if @os
    servers = servers.where(docker_status: DOCKER_FILTERS[@state]) if DOCKER_FILTERS.key?(@state)
    @q = params[:q].to_s.strip.first(100)
    servers = servers.includes(:dns_records) if @q.present?
    health_state = @state unless DOCKER_FILTERS.key?(@state)
    servers = servers.to_a if health_state || @q.present?
    servers = servers.select { |server| server.health_state == health_state } if health_state
    servers = servers.select { |server| server.matches_search?(@q) } if @q.present?
    @view = fleet_view
    servers = servers.to_a.sort_by { |server| [ STATE_ORDER.fetch(server.health_state, 2), server.name.downcase ] } if @view == "grid"
    @pager = paginate(servers, per_page: PER_PAGE)
    @servers = @pager.records
    @load_history = Inventory::HealthSample.where(server_id: @servers.map(&:id)).since(24.hours.ago)
                                           .pluck(:server_id, :load_percent).group_by(&:first).transform_values { |rows| rows.map(&:last).compact }
    @insights = KeyInsights.new
    if Integration.enabled?(:uptime_kuma)
      @monitor_counts = UptimeKumaMonitor.attached.group(:server_id).pluck(:server_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE status = 0)"))
                                         .to_h { |server_id, total, down| [ server_id, [ total, down ] ] }
    end
  end

  TABS = %w[overview vulnerabilities packages services docker ports firewall schedules keys notes history].freeze
  NOTES_PER_PAGE = 20
  VULNERABILITIES_PER_PAGE = 100
  VULNERABILITY_PACKAGES_PER_PAGE = 50
  VULNERABILITY_VIEWS = %w[packages cves].freeze
  DOCKER_SECTIONS = %w[containers images vulnerabilities].freeze

  # Tabbed page (?tab=), only the requested tab is rendered.
  def show
    @integration_tabs = Integration.server_tabs
    @tab = params[:tab].presence_in(TABS + @integration_tabs.map { |tab| tab[:key] }) || "overview"
    if @tab == "notes"
      @pager = paginate(@server.notes.recent.includes(:user), per_page: NOTES_PER_PAGE)
      @notes = @pager.records
    end
    if @tab == "history"
      @pager = paginate(Activity.recent.where(server: @server).includes(:user, :server, :public_key), per_page: HISTORY_PER_PAGE)
      @activities = @pager.records
    end
    show_vulnerabilities if @tab == "vulnerabilities"
    show_docker if @tab == "docker"
    @health_history = @server.health_samples.since(24.hours.ago).pluck(:collected_at, :load_percent, :memory_percent, :disk_percent) if @tab == "overview"
  end

  def new
    @server = Server.new
  end

  def create
    @server = Server.new(server_params)

    if @server.save
      Activity.record!(:server_created, server: @server, address: "#{@server.username}@#{@server.host}:#{@server.port}")
      redirect_to server_path(@server), notice: t("servers_controller.created", server_name: @server.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @server.update(server_params)
      changed = @server.saved_changes.keys & %w[name host port username]
      Activity.record!(:server_updated, server: @server, changed: changed) if changed.any?
      redirect_to server_path(@server), notice: t("servers_controller.updated", server_name: @server.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Removes the server from Elio only: keys installed on the machine stay.
  def destroy
    active_temporary_accesses = @server.temporary_accesses.active.count
    @server.destroy!
    still_used = Server.exists?(host: @server.host, port: @server.port)
    Ssh::KnownHosts.forget(@server.host, @server.port) unless still_used
    Activity.record!(:server_deleted, server_name: @server.name, address: "#{@server.username}@#{@server.host}:#{@server.port}",
                                      active_temporary_accesses: active_temporary_accesses)

    redirect_to servers_path, notice: t("servers_controller.deleted", server_name: @server.name),
                              status: :see_other
  end

  private

  # By package (default) or by CVE, remembered in a cookie like the fleet view;
  # a package filter (?package=) asks for the CVE view.
  def vulnerability_view
    view = params[:view].presence_in(VULNERABILITY_VIEWS) || ("cves" if params[:package].present?)
    cookies.permanent[:elio_vulnerability_view] = { value: view, same_site: :lax, httponly: true } if view
    view || cookies[:elio_vulnerability_view].presence_in(VULNERABILITY_VIEWS) || "packages"
  end

  # Vulnerabilities tab: the server's own packages (those of its Docker
  # images are in the Docker tab), fixable first, most serious first
  # (?fixable=1, ?severity=, ?q=, ?package=).
  def show_vulnerabilities
    all = @server.server_vulnerabilities
    scope = all.host
    @vulnerability_counts = { total: scope.distinct.count(:cve), fixable: scope.fixable.distinct.count(:cve),
                              by_severity: scope.group(:severity).distinct.count(:cve),
                              images: all.images.distinct.count(:cve), image_count: all.images.distinct.count(:image) }
    @fixable_only = params[:fixable] == "1"
    @severity = params[:severity].presence_in(Vulnerability::SEVERITIES.keys)
    scope = scope.fixable if @fixable_only
    scope = scope.at_least(@severity) if @severity
    @vulnerability_query = params[:q].to_s.strip.first(100).presence
    scope = scope.search(@vulnerability_query) if @vulnerability_query
    @package = params[:package].to_s.strip.presence&.first(100)
    @vulnerability_view = vulnerability_view
    if @vulnerability_view == "packages"
      @package_groups = PackageVulnerabilities.new(scope, server: @server).groups
      @pager = paginate(@package_groups, per_page: VULNERABILITY_PACKAGES_PER_PAGE)
      @package_groups = @pager.records
    else
      scope = scope.where(source_package: @package) if @package
      @sort = params[:sort] == "score" ? "score" : nil
      scope = (@sort ? scope.by_score : scope.ranked).includes(:rating)
      @pager = paginate(scope, per_page: VULNERABILITIES_PER_PAGE)
      @vulnerabilities = @pager.records
    end
  end

  # Docker tab in sections (?section=): containers, images, or the
  # vulnerabilities of the images by image then package.
  def show_docker
    @docker_section = params[:section].presence_in(DOCKER_SECTIONS) || "containers"
    images = @server.server_vulnerabilities.images
    @image_vulnerability_count = images.distinct.count(:cve)
    @image_fixable_count = images.fixable.distinct.count(:cve)
    return unless @docker_section == "vulnerabilities"

    @pager = paginate(PackageVulnerabilities.new(images, server: @server).groups, per_page: VULNERABILITY_PACKAGES_PER_PAGE)
    @package_groups = @pager.records
  end

  # List (dense table) or grid (cards): ?view=, remembered in a cookie.
  def fleet_view
    view = params[:view].presence_in(VIEWS)
    cookies.permanent[:elio_fleet_view] = { value: view, same_site: :lax, httponly: true } if view
    view || cookies[:elio_fleet_view].presence_in(VIEWS) || "list"
  end

  def set_server
    @server = Server.find(params[:id])
  end

  def server_params
    params.expect(server: [ :name, :host, :port, :username, :extra_addresses_text, server_group_ids: [] ])
  end
end
