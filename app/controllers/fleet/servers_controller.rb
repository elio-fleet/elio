class ServersController < ApplicationController
  PER_PAGE = 100
  VIEWS = %w[list grid].freeze
  # Grid: the problems first.
  STATE_ORDER = { "crit" => 0, "off" => 0, "warn" => 1, "unknown" => 2, "ok" => 3 }.freeze
  HISTORY_PER_PAGE = 30
  LATEST_EVENTS = 5

  require_permission :operate, only: %i[new create edit update destroy test_connection]

  before_action :set_server, only: %i[show edit update destroy]

  # State filter on the Docker state (servers.docker_status) instead of the health.
  DOCKER_FILTERS = { "docker_warn" => "warn", "docker_crit" => "crit" }.freeze

  def index
    @groups = ServerGroup.order(:name)
    @group = @groups.find { |group| group.id.to_s == params[:group].to_s } if params[:group].present?
    @os_names = Server.where.not(os_name: nil).distinct.order(:os_name).pluck(:os_name)
    @os = params[:os].presence_in(@os_names)
    @state = params[:state].presence_in(Server::HEALTH_STATES + %w[off] + DOCKER_FILTERS.keys)
    all_servers = Server.includes(:inventory_snapshots).to_a
    @summary = FleetSummary.new(all_servers)
    @state_counts = all_servers.map(&:health_state).tally.merge(all_servers.filter_map { |server| "docker_#{server.docker_status}" if server.docker_status.in?(%w[warn crit]) }.tally)
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
    @sort = ServerSort.new(params[:sort], params[:dir])
    servers = @sort.apply(servers) if @sort.active?
    return send_csv(ServerExport.new(servers)) if request.format.csv?

    @pager = paginate(servers, per_page: PER_PAGE)
    @servers = @pager.records
    @load_history = Inventory::HealthSample.where(server_id: @servers.map(&:id)).since(24.hours.ago)
                                           .pluck(:server_id, :load_percent).group_by(&:first).transform_values { |rows| rows.map(&:last).compact }
    @insights = KeyInsights.new
  end

  TABS = %w[overview vulnerabilities packages services docker firewall schedules keys journal].freeze
  # Former tabs, now inside another one (bookmarks, links of old notifications).
  MOVED_TABS = { "ports" => [ "firewall", nil ], "notes" => [ "journal", nil ], "history" => [ "journal", nil ], "ovh" => [ nil, "server-hosting" ] }.freeze
  VULNERABILITIES_PER_PAGE = 100
  VULNERABILITY_PACKAGES_PER_PAGE = 50
  VULNERABILITY_VIEWS = %w[packages cves].freeze
  DOCKER_SECTIONS = %w[containers images vulnerabilities].freeze

  # Tabbed page (?tab=), only the requested tab is rendered.
  def show
    if (moved = MOVED_TABS[params[:tab]])
      tab, anchor = moved
      return redirect_to server_path(@server, tab: tab, anchor: anchor), status: :moved_permanently
    end

    @integration_tabs = Integration.server_tabs
    tab_keys = TABS + @integration_tabs.map { |tab| tab[:key] }
    remembered = remembered_tabs[@server.id.to_s].presence_in(tab_keys - [ "overview" ])
    return redirect_to server_path(@server, tab: remembered) if remembered && request.query_parameters.empty?

    @tab = params[:tab].presence_in(tab_keys) || "overview"
    remember_tab(@tab) if params[:tab] == @tab
    show_journal if @tab == "journal"
    show_vulnerabilities if @tab == "vulnerabilities"
    show_docker if @tab == "docker"
    show_overview if @tab == "overview"
    @service_units = Inventory::ServiceUnits.new(@server, state: params[:state], query: params[:q]) if @tab == "services"
  end

  # Overview tab: 24-hour sparklines, charts over ?period= (24 h, 7 or 30
  # days), the disk trend and the latest events.
  def show_overview
    @chart_history = Inventory::HealthHistory.new(@server, period: params[:period])
    @health_history = (@chart_history.period.key == Inventory::HealthHistory::DEFAULT ? @chart_history : Inventory::HealthHistory.new(@server)).points
    @disk_trend = Inventory::DiskTrend.new(@server)
    @latest_events = Activity.recent.where(server: @server).includes(:user, :server, :public_key).limit(LATEST_EVENTS)
  end
  private :show_overview

  # ?from=<id>: a copy of that server (port, user, groups), to fill in the
  # name and the host.
  def new
    @source = Server.find_by(id: params[:from]) if params[:from].present?
    @server = @source ? Server.new(port: @source.port, username: @source.username, server_group_ids: @source.server_group_ids) : Server.new
  end

  # The journal of a server (ServerJournal): its notes and its activities on
  # one timeline, newest first, HISTORY_PER_PAGE at a time, filtered and searched.
  def show_journal
    @server_journal = ServerJournal.new(@server, params)
    @journal_page = [ params[:page].to_i, 1 ].max
    @journal, @journal_more = @server_journal.page(@journal_page, per_page: HISTORY_PER_PAGE)
  end
  private :show_journal

  def create
    @server = Server.new(server_params)

    if @server.save
      Activity.record!(:server_created, server: @server, address: "#{@server.username}@#{@server.host}:#{@server.port}")
      Inventory::FirstCollectJob.perform_later(@server)
      redirect_to server_path(@server), notice: t("servers_controller.created", server_name: @server.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    group_ids = @server.server_group_ids
    if @server.update(server_params)
      changed = @server.saved_changes.keys & %w[name host port username expected_ports expected_containers health_thresholds]
      Activity.record!(:server_updated, server: @server, changed: changed) if changed.any?
      # Expected ports and thresholds come from the server and its groups.
      health_inputs = changed.intersect?(%w[expected_ports expected_containers health_thresholds]) || group_ids.sort != @server.server_group_ids.sort
      @server.refresh_health! if health_inputs && @server.health_status.present?
      redirect_to server_path(@server), notice: t("servers_controller.updated", server_name: @server.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Tries the SSH values of the form (host, port, user) without saving:
  # connection, Elio's key, host key. Answers in the form (Turbo Stream).
  def test_connection
    @server = Server.new(params.expect(server: %i[host port username]))
    @server.validate
    errors = @server.errors.select { |error| error.attribute.in?(%i[host port username]) && error.type != :taken }
    @result = errors.any? ? Ssh::Check::Result.new(success: false, message: t("servers_controller.connection_invalid"), details: errors.map(&:full_message).to_sentence) : Ssh::Check.call(@server, privilege: true)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("server-connection-test", partial: "servers/connection_test", locals: { server: @server, result: @result }) }
      format.html { redirect_to new_server_path }
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
  # a package filter (?package=) asks for the CVE view without remembering it:
  # opening the CVEs of one package is not choosing the CVE view for good.
  def vulnerability_view
    return "cves" if params[:package].present?

    view = params[:view].presence_in(VULNERABILITY_VIEWS)
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
    # What to run to fix everything that can be, whatever the filters (the system and the Docker images).
    @fix_commands = Vulnerabilities::FixCommands.new(@server, all.fixable) if @vulnerability_counts[:fixable].positive? || all.images.fixable.exists?
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

  # Last tab opened on each server page, by server id: a link to a server
  # without ?tab= opens it again (a convenience of this browser, in a cookie
  # like the fleet view; the Overview tab link carries ?tab=overview).
  SERVER_TABS_COOKIE = :elio_server_tabs
  REMEMBERED_TABS = 50 # servers, the most recent ones (cookie size)

  def remembered_tabs
    tabs = JSON.parse(cookies[SERVER_TABS_COOKIE].to_s)
    tabs.is_a?(Hash) ? tabs : {}
  rescue JSON::ParserError
    {}
  end

  # A link prefetched on hover is not an opened tab.
  def remember_tab(tab)
    return if request.headers["X-Sec-Purpose"] == "prefetch"

    tabs = remembered_tabs.except(@server.id.to_s)
    tabs[@server.id.to_s] = tab unless tab == "overview"
    cookies.permanent[SERVER_TABS_COOKIE] = { value: tabs.to_a.last(REMEMBERED_TABS).to_h.to_json, same_site: :lax, httponly: true }
  end

  def send_csv(export)
    send_data export.to_csv, filename: export.filename, type: :csv, disposition: "attachment"
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
    params.expect(server: [ :name, :host, :port, :username, :extra_addresses_text, :expected_ports, :expected_containers, server_group_ids: [],
                            health_thresholds: Inventory::HealthThresholds::KEYS ])
  end
end
