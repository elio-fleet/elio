# The servers whose host key changed, with the old and new fingerprints, to
# trust several new keys at once after a planned reinstall. Admins only; each
# accepted key is logged as host_key_changed (Ssh::HostKeyTrust).
class HostKeyBatchesController < ApplicationController
  require_permission :administer

  def show
    @pending = PendingHostKey.all
  end

  def create
    chosen = params.permit(fingerprints: {})[:fingerprints]&.to_h || {}
    pairs = PendingHostKey.all.filter_map { |pending| [ pending.server, chosen[pending.server.id.to_s] ] if chosen[pending.server.id.to_s].present? }
    return redirect_to(host_key_batch_path, alert: t("host_key_batches_controller.choose_server")) if pairs.empty?

    accepted, failed = Ssh::HostKeyTrust.call_many(pairs, user: current_user).partition(&:accepted?)
    flash[:notice] = t("host_key_batches_controller.accepted", count: accepted.size) if accepted.any?
    flash[:alert] = t("host_key_batches_controller.failed", count: failed.size, servers: failed.map { |result| result.server.name }.join(", ")) if failed.any?
    redirect_to host_key_batch_path
  end
end
