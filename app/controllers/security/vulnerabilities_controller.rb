# Vulnerabilities of the whole fleet, in two tabs (?origin=): the packages of
# the servers (host, by default) or those of their Docker images (image),
# each by package or by CVE, whether a fix exists. Filters: ?q= (CVE or
# package), ?severity= (minimum), ?group= and ?server= (combined),
# ?fixable=1, ?exploited=1 (CISA KEV), ?epss= (minimum, in %). Fixable and
# most serious first. The same filters export as .csv / .json for an audit.
class VulnerabilitiesController < ApplicationController
  PER_PAGE = 100
  # Choices of the EPSS filter (probability of exploitation within 30 days, in %).
  EPSS_THRESHOLDS = %w[1 10 50].freeze
  # The concentration line is shown when one package holds at least this share of the CVEs.
  CONCENTRATION = 0.5
  Row = Data.define(:cve, :severity, :packages, :servers, :images, :fixable, :description, :source, :distro_status) do
    def rank = [ fixable ? 0 : 1, -Vulnerability.severity_rank(severity), -servers.size, cve ]
    def url = Vulnerability.url(cve, source)
  end

  # Everything about a CVE: description, the score of each provider with its
  # vector, exploitation, the packages and versions on the server it was
  # opened from (?server_id=), the other servers and images touched. In the
  # modal of the vulnerabilities lists (turbo-frame), or as a page.
  def show
    @cve = params[:cve].to_s.upcase
    @rows = ServerVulnerability.where(cve: @cve).includes(:server).to_a
    @feed_entries = Vulnerability.where(cve: @cve).order(:source, :release).to_a
    return head(:not_found) if @rows.empty? && @feed_entries.empty? && !CveScore.exists?(cve: @cve)

    @server = Server.find_by(id: params[:server_id])
    @server_rows = @server ? @rows.select { |row| row.server_id == @server.id } : []
    @rating = CveRating.find_by(cve: @cve)
    providers = ScoreProvider.all_providers
    @providers = providers.index_by(&:key)
    @scores = CveScore.where(cve: @cve).to_a.select { |score| @providers[score.provider_key] }.sort_by { |score| @providers[score.provider_key].position }
    scored = @scores.index_by(&:provider_key)
    # Every enabled CVSS provider (asked or not yet), and the disabled ones that have a score.
    @provider_scores = providers.select(&:cvss?).filter_map do |provider|
      [ provider, scored[provider.key] ] if provider.enabled? || scored[provider.key]&.score
    end
    @description = @feed_entries.filter_map(&:description).first || @rows.filter_map(&:description).first ||
                   @scores.filter_map { |score| score.data["description"] }.first
    @servers = @rows.group_by(&:server).sort_by { |server, _| server.name }
    # The commands to fix it: on the server the modal was opened from, or on each server.
    @fix_plans = (@server ? [ [ @server, @server_rows ] ] : @servers).filter_map do |server, rows|
      plans = Vulnerabilities::FixCommands.new(server, rows).plans
      [ server, plans ] if plans.any?
    end
    # What matched it to the packages: a feed (Debian, Ubuntu) or an image scanner.
    @match_sources = ServerVulnerability.by_match_source(@rows)
    render layout: !turbo_frame_request?
  end

  def index
    read_filters
    scope = ServerVulnerability.all
    scope = scope.where(server_id: Server.in_group(@group).select(:id)) if @group
    scope = scope.where(server_id: @server.id) if @server
    scope = filtered(scope)
    respond_to do |format|
      format.html { list(scope) }
      format.csv { export(scope, :csv) }
      format.json { export(scope, :json) }
    end
  end

  private

  def read_filters
    @groups = ServerGroup.order(:name)
    @group = @groups.find { |group| group.id.to_s == params[:group].to_s } if params[:group].present?
    @servers = (@group ? Server.in_group(@group) : Server.all).order(:name).to_a
    # A server outside the chosen group is dropped (the select would not show it).
    @server = @servers.find { |server| server.id.to_s == params[:server].to_s } if params[:server].present?
    @q = params[:q].to_s.strip.first(100)
    @severity = params[:severity].presence_in(Vulnerability::SEVERITIES.keys)
    @fixable_only = params[:fixable] == "1"
    @exploited_only = params[:exploited] == "1"
    @epss = params[:epss].presence_in(EPSS_THRESHOLDS)
    @origin = params[:origin].presence_in(ServerVulnerability::ORIGINS.keys) || "host"
  end

  # The filters after the scope of servers (group, server): the origin tabs count before them.
  def filtered(scope)
    @origin_counts = { "host" => scope.host.distinct.count(:cve), "image" => scope.images.distinct.count(:cve) } if request.format.html?
    scope = scope.at_least(@severity) if @severity
    scope = scope.fixable if @fixable_only
    scope = scope.where(cve: CveRating.where(exploited: true).select(:cve)) if @exploited_only
    scope = scope.where(cve: CveRating.where(epss: (@epss.to_d / 100)..).select(:cve)) if @epss
    scope = scope.where(origin: @origin)
    scope = scope.where("server_vulnerabilities.cve ILIKE :q OR server_vulnerabilities.source_package ILIKE :q", q: "%#{ServerVulnerability.sanitize_sql_like(@q)}%") if @q.present?
    scope
  end

  def filters?
    @q.present? || @severity || @fixable_only || @exploited_only || @epss || @group || @server
  end
  helper_method :filters?

  def export(scope, format)
    filters = { origin: @origin, q: @q, severity: @severity, group: @group&.name, server: @server&.name, fixable: @fixable_only, exploited: @exploited_only,
                epss_min_percent: @epss&.to_i }
    export = VulnerabilityExport.new(scope, filters: filters)
    send_data format == :csv ? export.to_csv : export.to_json, filename: export.filename(format), type: format, disposition: "attachment"
  end

  # One package that holds most of the CVEs (often the kernel): { package:, count:, share: }.
  def concentration(scope, total)
    return if total.zero?

    counts = scope.group(:source_package).distinct.count(:cve)
    package, count = counts.max_by { |name, value| [ value, name ] }
    { package: package, count: count, share: count.to_f / total } if counts.size > 1 && count >= total * CONCENTRATION
  end

  def list(scope)
    @feeds = VulnerabilityFeed.where.not(refreshed_at: nil).order(:source).to_a

    @view = params[:view].presence_in(%w[packages cves]) || ("cves" if @q.present? && @q.match?(/\ACVE-/i))
    cookies.permanent[:elio_vulnerability_view] = { value: @view, same_site: :lax, httponly: true } if @view
    @view ||= cookies[:elio_vulnerability_view].presence_in(%w[packages cves]) || "packages"
    if @view == "packages"
      @package_groups = PackageVulnerabilities.new(scope).groups
      # Separate counts: each uses an index, much faster than one query with several COUNT(DISTINCT … ) FILTER.
      @summary = { cves: scope.distinct.count(:cve), fixable: scope.fixable.distinct.count(:cve), servers: scope.distinct.count(:server_id),
                   serious: scope.fixable.at_least("high").distinct.count(:cve) }
      @concentration = concentration(scope, @summary[:cves])
      @pager = paginate(@package_groups, per_page: 50)
      @package_groups = @pager.records
      return
    end

    values = scope.group(:cve).pluck(
      :cve, PackageVulnerabilities::WORST_SEVERITY,
      Arel.sql("ARRAY_AGG(DISTINCT server_vulnerabilities.source_package)"), Arel.sql("ARRAY_AGG(DISTINCT server_vulnerabilities.server_id)"),
      Arel.sql("ARRAY_AGG(DISTINCT server_vulnerabilities.image) FILTER (WHERE server_vulnerabilities.image IS NOT NULL)"),
      Arel.sql("BOOL_OR(server_vulnerabilities.fixed_version IS NOT NULL)"), Arel.sql("MAX(server_vulnerabilities.description)"), Arel.sql("MIN(server_vulnerabilities.source)"),
      Arel.sql("MAX(server_vulnerabilities.distro_status) FILTER (WHERE server_vulnerabilities.fixed_version IS NULL)")
    )
    servers = Server.where(id: values.flat_map { |row| row[3] }.uniq).index_by(&:id)
    rows = values.map do |cve, severity, packages, server_ids, images, fixable, description, source, distro_status|
      Row.new(cve: cve, severity: severity, packages: packages.sort, servers: server_ids.filter_map { |id| servers[id] }.sort_by(&:name),
              images: Array(images).sort, fixable: fixable, description: description, source: source,
              distro_status: (distro_status unless fixable))
    end
    @summary = { cves: rows.size, fixable: rows.count(&:fixable), servers: servers.size,
                 serious: rows.count { |row| row.fixable && row.severity.in?(%w[critical high]) } }
    @concentration = concentration(scope, @summary[:cves])
    @pager = paginate(rows.sort_by(&:rank), per_page: PER_PAGE)
    @rows = @pager.records
    @ratings = CveRating.for(@rows.map(&:cve))
  end
end
