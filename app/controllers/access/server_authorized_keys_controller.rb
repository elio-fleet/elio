class ServerAuthorizedKeysController < ApplicationController
  include AuthorizedKeysRefresh

  require_permission :operate, only: :destroy

  before_action :set_server

  # Every account Elio can read (the login one; the others through root).
  def index
    @result = Keys::AuthorizedKeysReader.call_all(@server)
    record_ssh_status
    @app_key = SshKey.app_keys
    @public_keys_by_fingerprint = PublicKey.where(fingerprint: @result.keys.map(&:fingerprint)).index_by(&:fingerprint)
    @temporary_accesses = TemporaryAccess.active.where(server: @server).index_by { |access| [ access.unix_user, access.fingerprint ] }
  end

  # Removes the key whose base64 blob is params[:key] from the file of the
  # account params[:account] (the login one by default).
  def destroy
    @account = AuthorizedKeysAccount.for(@server, params[:account])
    return head(:unprocessable_content) unless @account

    name = params[:name].presence || t("server_authorized_keys_controller.unnamed")
    result = Keys::Revocation.call(@server, params.expect(:key), account: @account, key_name: params[:name].presence)
    target = t(@account.login? ? "server_authorized_keys_controller.target" : "server_authorized_keys_controller.target_account", server_name: @server.name, account: @account.unix_user)

    flash_type, message = if result.removed?
      [ :notice, t("server_authorized_keys_controller.deleted", name: name, target: target) ]
    elsif result.absent?
      [ :notice, t("server_authorized_keys_controller.absent", name: name, target: target) ]
    else
      [ :alert, t("server_authorized_keys_controller.failed", name: name, target: target, error_title: result.error_title, error_details: result.error_details) ]
    end

    respond_with_authorized_keys_refresh(@account, flash_type, message)
  end

  private

  # A successful read proves the app can log in (and refreshes the account's
  # snapshot); a refused key proves it cannot.
  def record_ssh_status
    if @result.success?
      @server.record_ssh_status!(true)
      AccountSnapshot.record_all!(@server, @result)
    elsif @result.reason == :key_refused
      @server.record_ssh_status!(false)
    end
  end

  def set_server
    @server = Server.find(params[:server_id])
  end
end
