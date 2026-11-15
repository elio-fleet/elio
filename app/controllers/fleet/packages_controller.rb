# Packages of the whole fleet: a search shows, for each matching package
# name, its versions (newest first for dpkg) with their repositories and the
# servers that have them, the exact name first; without a search, the pending
# security updates, by package (paged by name) or by server (?view=servers,
# with the apt command that installs them all, shown and never run by Elio),
# and as .csv for a spreadsheet.
class PackagesController < ApplicationController
  RESULTS_PER_PAGE = 25
  SECURITY_PER_PAGE = 50
  SERVERS_PER_PAGE = 20
  VIEWS = %w[packages servers].freeze

  def index
    return export if request.format.csv?

    @q = params[:q].to_s.strip.first(100)
    if @q.present?
      matching = Inventory::Package.search(@q)
      names = matching.distinct.order(:name).pluck(:name)
      @pager = paginate(names.partition { |name| name.casecmp?(@q) }.flatten, per_page: RESULTS_PER_PAGE)
      @results = matching.where(name: @pager.records).includes(:server).order(:name, :version).group_by(&:name)
      @results = @pager.records.to_h { |name| [ name, @results[name] ] }.compact
      @versions = @results.transform_values { |rows| newest_first(rows.group_by(&:version)) }
    else
      @view = VIEWS.include?(params[:view]) ? params[:view] : VIEWS.first
      @view == "servers" ? by_server : by_package
    end
    @servers_without_inventory = Server.where.not(id: Inventory::Package.select(:server_id)).count
  end

  private

  def by_package
    security = Inventory::Package.security
    @pager = paginate(security.distinct.order(:name).pluck(:name), per_page: SECURITY_PER_PAGE)
    @security = security.where(name: @pager.records).includes(:server).order(:name).group_by(&:name)
  end

  # Each server with security updates, its packages and the command to paste.
  def by_server
    @pager = paginate(Server.where(id: Inventory::Package.security.select(:server_id)).order(:name), per_page: SERVERS_PER_PAGE)
    packages = Inventory::Package.security.where(server_id: @pager.records.map(&:id)).order(:name).group_by(&:server_id)
    @by_server = @pager.records.to_h { |server| [ server, packages.fetch(server.id, []) ] }
  end

  def export
    export = Inventory::SecurityUpdateExport.new(Inventory::Package.security)
    send_data export.to_csv, filename: export.filename, type: :csv, disposition: "attachment"
  end

  # dpkg versions sorted like dpkg does, the newest first; others as they come.
  def newest_first(versions)
    return versions unless versions.values.first&.first&.manager == "dpkg"

    versions.sort { |(left, _), (right, _)| Inventory::DebianVersion.compare(right.to_s, left.to_s) }.to_h
  end
end
