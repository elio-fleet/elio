# "Coolify" page (Coolify extension): every resource of every connection
# (team / instance) with its server, what needs attention first; filters by
# problem and kind (the databases filter also shows the services holding
# one), by project, environment and state, a search by name or domain.
class CoolifyController < ApplicationController
  include RequiresIntegration

  PER_PAGE = 100
  FILTERS = %w[attention applications services databases unattached].freeze
  PROBLEM_SQL = "coolify_resources.status LIKE 'exited%' OR coolify_resources.status LIKE 'stopped%' OR coolify_resources.status LIKE '%:unhealthy' OR coolify_resources.status LIKE 'restarting%'".freeze
  # CoolifyHelper#coolify_state_key → its condition ("other" left out).
  STATE_SQL = { "healthy" => "coolify_resources.status = 'running:healthy'",
                "running" => "coolify_resources.status LIKE 'running%' AND coolify_resources.status NOT IN ('running:healthy', 'running:unhealthy')",
                "unhealthy" => "coolify_resources.status = 'running:unhealthy'",
                "restarting" => "coolify_resources.status LIKE 'restarting%'",
                "stopped" => "coolify_resources.status LIKE 'exited%' OR coolify_resources.status LIKE 'stopped%'" }.freeze

  requires_integration :coolify

  def index
    all = CoolifyResource.resources
    @projects = distinct_values(all, "project")
    @environments = distinct_values(all, "environment")
    @filter = params[:filter].presence_in(FILTERS)
    @q = params[:q].to_s.strip.first(100)
    @project = params[:project].presence_in(@projects)
    @environment = params[:environment].presence_in(@environments)
    @state = params[:state].presence_in(STATE_SQL.keys)
    @selects = { project: @project, environment: @environment, state: @state }.compact
    @counts = { total: all.count, attention: all.where(PROBLEM_SQL).count, unattached: all.where(server_id: nil).count,
                servers_outside: CoolifyResource.servers.where(server_id: nil).count }
    @connections = @integration.connections.to_a
    @unconnected = Integrations::Coolify.unconnected_servers.to_a

    resources = all.includes(:server, :connection)
    resources = case @filter
    when "attention" then resources.where(PROBLEM_SQL)
    when "unattached" then resources.where(server_id: nil)
    when "applications", "services" then resources.where(kind: @filter.delete_suffix("s"))
    when "databases" then resources.where("coolify_resources.kind = 'database' OR (coolify_resources.kind = 'service' AND jsonb_exists(coolify_resources.data, 'databases'))")
    else resources
    end
    resources = resources.where("coolify_resources.data->>'project' = ?", @project) if @project
    resources = resources.where("coolify_resources.data->>'environment' = ?", @environment) if @environment
    resources = resources.where(STATE_SQL.fetch(@state)) if @state
    if @q.present?
      resources = resources.where("coolify_resources.name ILIKE :q OR coolify_resources.data->>'domains' ILIKE :q", q: "%#{CoolifyResource.sanitize_sql_like(@q)}%")
    end
    @pager = paginate(resources.order(Arel.sql("CASE WHEN #{PROBLEM_SQL} THEN 0 ELSE 1 END"), :name, :id), per_page: PER_PAGE)
  end

  private

  # The projects (or environments) Coolify names, for the filter selects.
  def distinct_values(resources, key)
    resources.distinct.pluck(Arel.sql("coolify_resources.data->>'#{key}'")).compact.sort_by { |value| value.downcase }
  end
end
