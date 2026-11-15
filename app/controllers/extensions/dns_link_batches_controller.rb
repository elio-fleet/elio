# Attaches the names of several DNS records at once (the boxes ticked on the
# DNS page) to one server, to none (server_id "none"), or back to the
# automatic attachment ("auto"): one DnsLink per name, as DnsLinksController
# does for one.
class DnsLinkBatchesController < ApplicationController
  AUTOMATIC = "auto".freeze
  NONE = "none".freeze

  require_permission :operate

  def create
    names = DnsRecord.where(id: Array.wrap(params[:record_ids]).grep(String)).distinct.pluck(:name)
    return redirect_back_or_to(dns_records_path, alert: t("dns_link_batches_controller.none_selected")) if names.empty? || params[:server_id].blank?

    previous = Server.where(id: DnsRecord.where(name: names).attached.select(:server_id)).to_a
    if params[:server_id] == AUTOMATIC
      DnsLink.where(name: names).delete_all
      notice = t("dns_link_batches_controller.automatic", count: names.size)
    else
      server = Server.find(params[:server_id]) unless params[:server_id] == NONE
      DnsLink.transaction { names.each { |name| DnsLink.find_or_initialize_by(name: name).update!(server: server, user: current_user) } }
      notice = server ? t("dns_link_batches_controller.attached", count: names.size, server_name: server.name) : t("dns_link_batches_controller.detached", count: names.size)
    end
    (Dns::Matcher.call + previous).uniq.each(&:refresh_health!)
    redirect_back_or_to dns_records_path, notice: notice
  end
end
