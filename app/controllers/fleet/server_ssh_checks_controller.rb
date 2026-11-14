class ServerSshChecksController < ApplicationController
  # Checks SSH access to a server and renders its SSH frame (server page,
  # loaded on display and on refresh).
  def show
    @server = Server.find(params[:server_id])
    @result = Ssh::Check.call(@server)
    # Only a refused key says the app lost its access: a changed host key is
    # another problem (logged as such), a missing key a setup step.
    if @result.success? || @result.reason == :key_refused
      @server.record_ssh_status!(@result.success?)
    elsif @result.reason == :host_key_changed
      @server.record_host_key_mismatch!(@result.host_key[:new])
    end
  end
end
