# "OVHcloud" (extension): services (dedicated, VPS, instances) and IP blocks,
# with the server each one belongs to. The DNS records are on the DNS page
# (?tab=dns, from older links, goes there).
class OvhController < ApplicationController
  include RequiresIntegration

  PER_PAGE = 100
  TABS = %w[services ips].freeze

  requires_integration :ovh

  def index
    return redirect_to(dns_records_path(source: "ovh")) if params[:tab] == "dns"

    @tab = params[:tab].presence_in(TABS) || "services"
    @q = params[:q].to_s.strip.first(100)
    @counts = OvhResource.group(:kind).count
    @unattached_services = OvhResource.services.unattached.count
    @dns_count = DnsRecord.of_source("ovh").count
    @expiring = Integrations::Ovh.expiring_services(@integration).count

    scope = case @tab
    when "services" then OvhResource.services.order(:kind, :name)
    else OvhResource.of_kind("ip").order(:name)
    end
    scope = scope.unattached if params[:unattached] == "1"
    scope = scope.where("ovh_resources.name ILIKE :q OR ovh_resources.data::text ILIKE :q", q: "%#{OvhResource.sanitize_sql_like(@q)}%") if @q.present?
    @pager = paginate(scope.includes(:server), per_page: PER_PAGE)
  end
end
