# Packages of the whole fleet: a search shows, for each matching package
# name, its versions (newest first for dpkg) with their repositories and the
# servers that have them, the exact name first; without a search, the pending
# security updates. Paged by package name.
class PackagesController < ApplicationController
  RESULTS_PER_PAGE = 25
  SECURITY_PER_PAGE = 50

  def index
    @q = params[:q].to_s.strip.first(100)
    if @q.present?
      matching = Inventory::Package.search(@q)
      names = matching.distinct.order(:name).pluck(:name)
      @pager = paginate(names.partition { |name| name.casecmp?(@q) }.flatten, per_page: RESULTS_PER_PAGE)
      @results = matching.where(name: @pager.records).includes(:server).order(:name, :version).group_by(&:name)
      @results = @pager.records.to_h { |name| [ name, @results[name] ] }.compact
      @versions = @results.transform_values { |rows| newest_first(rows.group_by(&:version)) }
    else
      security = Inventory::Package.security
      @pager = paginate(security.distinct.order(:name).pluck(:name), per_page: SECURITY_PER_PAGE)
      @security = security.where(name: @pager.records).includes(:server).order(:name).group_by(&:name)
    end
    @servers_without_inventory = Server.where.not(id: Inventory::Package.select(:server_id)).count
  end

  private

  # dpkg versions sorted like dpkg does, the newest first; others as they come.
  def newest_first(versions)
    return versions unless versions.values.first&.first&.manager == "dpkg"

    versions.sort { |(left, _), (right, _)| Inventory::DebianVersion.compare(right.to_s, left.to_s) }.to_h
  end
end
