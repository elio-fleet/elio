# The temporary accesses of a server: those in progress, which an operator can
# extend (Keys::AccessExtension), and the ended ones (history).
class TemporaryAccessesController < ApplicationController
  HISTORY_LIMIT = 50

  require_permission :operate, only: :update

  before_action :set_server

  def index
    accesses = @server.temporary_accesses.includes(:public_key)
    @active = accesses.active.order(:expires_at)
    @history = accesses.ended.order(ended_at: :desc, id: :desc).limit(HISTORY_LIMIT)
  end

  def update
    access = @server.temporary_accesses.find(params[:id])
    duration = requested_duration
    result = Keys::AccessExtension.call(access, duration)

    if result.success?
      redirect_back_with(:notice, t("temporary_accesses_controller.extended", name: access.public_key&.name || access.fingerprint, account: access.unix_user,
                                                                               label: TemporaryAccess.label_for(duration), date: l(access.expires_at, format: :short)))
    else
      redirect_back_with(:alert, t("temporary_accesses_controller.extend_failed", error_title: result.error_title, error_details: result.error_details))
    end
  end

  private

  def requested_duration
    TemporaryAccess.duration_for(params[:duration])
  rescue ArgumentError
    raise ActionController::BadRequest, "Invalid duration"
  end

  def set_server
    @server = Server.find(params[:server_id])
  end

  def redirect_back_with(type, message)
    redirect_to server_temporary_accesses_path(@server), flash: { type => message }, status: :see_other
  end
end
