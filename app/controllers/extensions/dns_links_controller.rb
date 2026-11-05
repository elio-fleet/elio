# Manual attachment of a DNS name to a server (or to none), for every record
# of that name whatever its source (DnsLink), kept across synchronizations;
# DELETE returns to the automatic attachment. Applied at once (Dns::Matcher).
class DnsLinksController < ApplicationController
  require_permission :operate

  before_action :set_record

  def create
    server = Server.find(params[:server_id]) if params[:server_id].present?
    DnsLink.find_or_initialize_by(name: @record.name).update!(server: server, user: current_user)
    rematch
    redirect_back_or_to dns_records_path, notice: server ? t("dns_links_controller.attached", name: @record.name, server_name: server.name) : t("dns_links_controller.detached", name: @record.name)
  end

  def destroy
    DnsLink.where(name: @record.name).delete_all
    rematch
    redirect_back_or_to dns_records_path, notice: t("dns_links_controller.automatic", name: @record.name), status: :see_other
  end

  private

  def set_record
    @record = DnsRecord.find(params[:dns_record_id])
  end

  def rematch
    previous = DnsRecord.where(name: @record.name).filter_map(&:server)
    (Dns::Matcher.call + previous).uniq.each(&:refresh_health!)
  end
end
