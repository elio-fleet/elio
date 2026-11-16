# Grants a keyring key access to several servers at once, revokes one access,
# or revokes every known access (someone leaves), from the keyring key page.
# The results of a bulk action come with a button that runs it again on the
# failures only.
class PublicKeyAccessesController < ApplicationController
  require_permission :operate

  before_action :set_public_key

  def create
    servers = Server.where(id: params[:server_ids]).order(:name)
    return redirect_to(public_key_path(@public_key), alert: t("public_key_accesses_controller.choose_server")) if servers.empty?

    unix_user = params[:unix_user].to_s.strip.presence
    return redirect_to(public_key_path(@public_key), alert: t("server_authorizations_controller.invalid_account"), status: :see_other) if unix_user && !unix_user.match?(AuthorizedKeysAccount::NAME_FORMAT)

    @results = Keys::BulkAccess.grant([ @public_key ], servers, duration: requested_duration, unix_user: unix_user)
    @again = { method: :post, params: { server_ids: @results.select(&:error?).map { |result| result.server.id }.uniq, duration: params[:duration], unix_user: unix_user }.compact_blank }

    respond_with_accesses(:notice, t("public_key_accesses_controller.done", succeeded: @results.count { |result| !result.error? }, count: @results.size))
  end

  # Removes the key from every account where the last key reads saw it. A
  # retry runs it again: the accounts it was removed from are no longer listed.
  def destroy_all
    results = Keys::BulkAccess.revoke(@public_key)
    return respond_with_accesses(:alert, t("public_key_accesses_controller.no_access")) if results.empty?

    @results, @results_target, @again = results, "revoke-results", { method: :delete, params: {} }
    respond_with_accesses(results.any?(&:error?) ? :alert : :notice, t("public_key_accesses_controller.removed_everywhere", succeeded: @results.count { |result| !result.error? }, count: @results.size))
  end

  def destroy
    server = Server.find(params.expect(:server_id))
    account = AuthorizedKeysAccount.for(server, params[:account])
    return head(:unprocessable_content) unless account

    result = Keys::Revocation.call(server, @public_key.authorized_key.key, account: account, key_name: @public_key.authorized_key.comment || @public_key.name, public_key: @public_key)

    if result.success?
      respond_with_accesses(:notice, t("public_key_accesses_controller.removed", public_key_name: @public_key.name, server_name: account.login? ? server.name : "#{server.name} (#{account.unix_user})"))
    else
      respond_with_accesses(:alert, t("public_key_accesses_controller.remove_failed", error_title: result.error_title, error_details: result.error_details))
    end
  end

  private

  def set_public_key
    @public_key = PublicKey.find(params[:public_key_id])
  end

  def requested_duration
    TemporaryAccess.duration_for(params[:duration]) if params[:duration].present?
  rescue ArgumentError
    raise ActionController::BadRequest, "Invalid duration"
  end

  def respond_with_accesses(flash_type, message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[flash_type] = message
        streams = [ turbo_stream.replace("key-accesses", partial: "public_keys/accesses", locals: { public_key: @public_key }),
                    turbo_stream.update("flash", partial: "shared/flash") ]
        streams << turbo_stream.update(@results_target || "bulk-results", partial: "public_keys/bulk_results", locals: { public_key: @public_key, results: @results, again: @again }) if @results
        render turbo_stream: streams
      end
      format.html { redirect_to public_key_path(@public_key), flash: { flash_type => message }, status: :see_other }
    end
  end
end
