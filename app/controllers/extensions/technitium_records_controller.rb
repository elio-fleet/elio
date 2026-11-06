# The DNS records read from Technitium DNS Server (extension), with the server
# each one points to. Filters: ?filter=outside (A / AAAA to an IP outside the
# fleet), unattached, ?q= (name or value), ?zone=.
class TechnitiumRecordsController < ApplicationController
  include RequiresIntegration

  requires_integration :technitium

  PER_PAGE = 100
  FILTERS = %w[outside unattached].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS)
    @zones = TechnitiumRecord.distinct.order(:zone).pluck(:zone)
    @zone = params[:zone].presence_in(@zones)
    @q = params[:q].to_s.strip.first(100)
    scope = TechnitiumRecord.includes(:server).order(:zone, :name, :record_type, :value)
    scope = scope.outside_fleet if @filter == "outside"
    scope = scope.unattached if @filter == "unattached"
    scope = scope.where(zone: @zone) if @zone
    scope = scope.where("technitium_records.name ILIKE :q OR technitium_records.value ILIKE :q", q: "%#{TechnitiumRecord.sanitize_sql_like(@q)}%") if @q.present?
    @counts = { total: TechnitiumRecord.count, outside: TechnitiumRecord.outside_fleet.count, unattached: TechnitiumRecord.unattached.count,
                servers_without: Server.where.not(id: TechnitiumRecord.attached.select(:server_id)).count }
    @pager = paginate(scope, per_page: PER_PAGE)
    @records = @pager.records
  end
end
