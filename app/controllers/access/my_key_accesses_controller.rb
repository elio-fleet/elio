# "Add my key temporarily" on the server page: the signed-in user adds one of
# their keys (AccountKeysController) to an account of the server for a
# limited time, extends it (a new grant replaces the expiry), or removes it.
class MyKeyAccessesController < ApplicationController
  DEFAULT_DURATION = "60"

  require_permission :operate

  before_action :set_server

  def create
    public_key = current_user.public_keys.find_by(id: params[:public_key_id]) || current_user.public_keys.first
    return redirect_to(account_path(anchor: "my-keys"), alert: t(".no_key"), status: :see_other) unless public_key

    account = AuthorizedKeysAccount.for(@server, params[:account]) or return back_with(:alert, t("server_authorizations_controller.invalid_account"))
    duration = TemporaryAccess.duration_for(params[:duration].presence || DEFAULT_DURATION)
    result = Keys::AccessGrant.call(@server, public_key, account: account, duration: duration)

    if result.success?
      back_with(:notice, t(".added", name: public_key.name, account: account.unix_user, label: TemporaryAccess.label_for(duration), time: l(duration.from_now, format: :short)))
    else
      back_with(:alert, t(".failed", error_title: result.error_title, error_details: result.error_details))
    end
  rescue ArgumentError
    raise ActionController::BadRequest, "Invalid duration"
  end

  def destroy
    access = TemporaryAccess.active.where(server: @server, public_key: current_user.public_keys).find(params[:id])
    result = Keys::Revocation.call(@server, access.key_blob, account: access.account, public_key: access.public_key, key_name: access.public_key&.name)

    if result.success?
      access.end!
      back_with(:notice, t(".removed", name: access.public_key&.name, account: access.unix_user))
    else
      back_with(:alert, t(".failed", error_title: result.error_title, error_details: result.error_details))
    end
  end

  private

  def set_server
    @server = Server.find(params[:server_id])
  end

  def back_with(type, message)
    redirect_to server_path(@server, tab: params[:tab].presence_in(%w[keys])), flash: { type => message }, status: :see_other
  end
end
