class ServerAuthorizedKeysController < ApplicationController
  include AuthorizedKeysRefresh

  require_permission :operate, only: :destroy

  before_action :set_server

  # Every account Elio can read (the login one; the others through root).
  def index
    assign_authorized_keys(@server, Keys::AuthorizedKeysReader.call_all(@server))
  end

  # Removes the key whose base64 blob is params[:key] from the file of the
  # account params[:account] (the login one by default), then shows the list
  # read on the same connection.
  def destroy
    @account = AuthorizedKeysAccount.for(@server, params[:account])
    return head(:unprocessable_content) unless @account

    name = params[:name].presence || t("server_authorized_keys_controller.unnamed")
    change = Keys::ServerKeysChange.revoke(@server, params.expect(:key), account: @account, key_name: params[:name].presence)
    result = change.outcomes.first.last
    target = t(@account.login? ? "server_authorized_keys_controller.target" : "server_authorized_keys_controller.target_account", server_name: @server.name, account: @account.unix_user)

    flash_type, message = if result.removed?
      [ :notice, t("server_authorized_keys_controller.deleted", name: name, target: target) ]
    elsif result.absent?
      [ :notice, t("server_authorized_keys_controller.absent", name: name, target: target) ]
    else
      [ :alert, t("server_authorized_keys_controller.failed", name: name, target: target, error_title: result.error_title, error_details: result.error_details) ]
    end

    respond_with_authorized_keys_refresh(@server, change.read, flash_type, message)
  end

  private

  def set_server
    @server = Server.find(params[:server_id])
  end
end
