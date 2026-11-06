# The DNS of the fleet (DnsRecord, from the extensions that are DNS sources:
# OVHcloud, Technitium), with the server each record points to. Filters:
# ?filter=outside (A / AAAA to an IP outside the fleet), unattached or
# conflicts (a name whose records differ between sources),
# ?source=, ?zone=, ?q= (name or value). 404 without any DNS source.
class DnsRecordsController < ApplicationController
  PER_PAGE = 100
  FILTERS = %w[outside unattached conflicts].freeze

  before_action { raise ActionController::RoutingError, "no DNS source" unless Dns.enabled? }

  def index
    @sources = Dns.source_integrations
    @filter = params[:filter].presence_in(FILTERS)
    @source = params[:source].presence_in(DnsRecord::SOURCES.keys)
    @zones = DnsRecord.distinct.order(:zone).pluck(:zone)
    @zone = params[:zone].presence_in(@zones)
    @q = params[:q].to_s.strip.first(100)
    scope = DnsRecord.includes(:server).order(:zone, :name, :record_type, :source, :value)
    scope = scope.outside_fleet if @filter == "outside"
    scope = scope.unattached if @filter == "unattached"
    @conflicts = DnsRecord.conflicting_names.to_set
    scope = scope.where(name: @conflicts.to_a) if @filter == "conflicts"
    scope = scope.of_source(@source) if @source
    scope = scope.where(zone: @zone) if @zone
    scope = scope.where("dns_records.name ILIKE :q OR dns_records.value ILIKE :q", q: "%#{DnsRecord.sanitize_sql_like(@q)}%") if @q.present?
    @counts = { total: DnsRecord.count, outside: DnsRecord.outside_fleet.count, unattached: DnsRecord.unattached.count,
                servers_without: Server.where.not(id: DnsRecord.attached.select(:server_id)).count, conflicts: @conflicts.size }
    @pager = paginate(scope, per_page: PER_PAGE)
    @records = @pager.records
  end
end
