# Trusting the new host key of a server (reinstalled…), admins only. Only the
# fingerprint the admin was shown is accepted (Ssh::HostKeyTrust).
class ServerHostKeysController < ApplicationController
  require_permission :administer

  def create
    server = Server.find(params[:server_id])
    result = Ssh::HostKeyTrust.call(server, params.expect(:fingerprint), user: current_user)

    if result.accepted?
      redirect_to server_path(server), notice: t("server_host_keys_controller.accepted", server_name: server.name)
    else
      redirect_to server_path(server), alert: t("server_host_keys_controller.#{result.status}", expected: result.fingerprint)
    end
  end
end
