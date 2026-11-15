class ServerSshDiagnosesController < ApplicationController
  # Runs the step-by-step SSH diagnosis (Ssh::Diagnosis) and renders it in
  # the SSH frame of the server page, in place of the failed check. Records
  # nothing: the check of the frame (ServerSshChecksController) does.
  def show
    @server = Server.find(params[:server_id])
    @result = Ssh::Diagnosis.call(@server)
  end
end
