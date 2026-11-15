# "Ignore" an unexpected public port in one click: adds it to the server's
# own expected ports (Server#expected_ports), like editing the server.
class ServerExpectedPortsController < ApplicationController
  require_permission :operate

  def create
    server = Server.find(params[:server_id])
    port = params.expect(:port).to_i
    proto = params.expect(:proto).presence_in(%w[tcp udp])
    return redirect_to(server_path(server, tab: "firewall"), alert: t("server_expected_ports_controller.invalid")) unless proto && port.between?(1, 65_535)

    if server.add_expected_port!(port, proto)
      Activity.record!(:server_updated, server: server, changed: %w[expected_ports], port: "#{port}/#{proto}")
      server.refresh_health! if server.health_status.present?
    end
    redirect_to server_path(server, tab: "firewall"), notice: t("server_expected_ports_controller.added", port: "#{port}/#{proto}", server_name: server.name)
  end
end
