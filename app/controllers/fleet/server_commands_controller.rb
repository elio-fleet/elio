# Every command Elio may run on a server, read from config/ssh_commands.yml
# (Ssh::Commands) and shown as the variant of the server's distribution
# family: what Elio does there, for anyone to review. Read-only page, no SSH.
class ServerCommandsController < ApplicationController
  def index
    @server = Server.find(params[:server_id])
    os = @server.inventory("os")&.data || {}
    # Same order as Ssh::Connection#distros (ID, then ID_LIKE); [] until the
    # first inventory, when the default variants are shown.
    @distros = Ssh::Commands.parse_distros([ os["id"], os["id_like"] ].compact.join(" "))
    @commands_by_role = Ssh::Commands.all.values.group_by(&:role)
  end
end
