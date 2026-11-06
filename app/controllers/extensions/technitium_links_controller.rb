# Manual attachment of a DNS name read from Technitium to a server (or to
# none), kept across synchronizations (IntegrationLink, by name: every record
# of the name follows); DELETE returns to the automatic one (next sync).
class TechnitiumLinksController < ApplicationController
  include RequiresIntegration

  requires_integration :technitium
  require_permission :operate

  def create
    record = TechnitiumRecord.find(params[:technitium_record_id])
    server = Server.find(params[:server_id]) if params[:server_id].present?
    @integration.links.find_or_initialize_by(external_id: record.link_key).update!(server: server, user: current_user)
    records = TechnitiumRecord.where(name: record.name)
    previous = records.filter_map(&:server)
    records.update_all(server_id: server&.id, matched_by: (server ? "manual" : nil), matched_address: nil)
    [ *previous, server ].compact.uniq.each(&:refresh_health!)

    redirect_back_or_to technitium_records_path, notice: server ? t("technitium_links_controller.attached", name: record.name, server_name: server.name) : t("technitium_links_controller.detached", name: record.name)
  end

  def destroy
    record = TechnitiumRecord.find(params[:technitium_record_id])
    @integration.links.where(external_id: record.link_key).delete_all
    task = @integration.enqueue_sync!

    redirect_back_or_to task_path(task), notice: t("technitium_links_controller.automatic", name: record.name), status: :see_other
  end
end
