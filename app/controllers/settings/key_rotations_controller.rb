module Settings
  # Replacing Elio's key without downtime (see KeyRotation), admins only.
  class KeyRotationsController < ApplicationController
    require_permission :administer

    before_action :set_rotation, only: %i[show retry resume finalize]

    def create
      rotation = KeyRotation.start!(by: current_user)
      Activity.record!(:ssh_key_rotation_started, servers: rotation.servers_count)
      RotateSshKeyJob.perform_later(rotation)
      redirect_to settings_key_rotation_path(rotation), notice: t("key_rotations_controller.started")
    rescue KeyRotation::AlreadyRunning
      redirect_to settings_path, alert: t("key_rotations_controller.already_running")
    end

    def show
    end

    def retry
      return redirect_to(settings_key_rotation_path(@rotation), alert: t("key_rotations_controller.nothing_to_retry")) unless @rotation.status == :partial

      @rotation.update!(finished_at: nil)
      RotateSshKeyJob.perform_later(@rotation, retry_failed: true)
      redirect_to settings_key_rotation_path(@rotation), notice: t("key_rotations_controller.retrying")
    end

    # Starts the job again on a rotation that stopped moving (its job was lost):
    # it goes on with the servers not done yet.
    def resume
      return redirect_to(settings_key_rotation_path(@rotation), alert: t("key_rotations_controller.nothing_to_resume")) unless @rotation.stalled?

      @rotation.touch
      RotateSshKeyJob.perform_later(@rotation)
      redirect_to settings_key_rotation_path(@rotation), notice: t("key_rotations_controller.resuming")
    end

    # Activates the new key although some servers failed (they lose Elio's access).
    def finalize
      return redirect_to(settings_key_rotation_path(@rotation), alert: t("key_rotations_controller.cannot_finalize")) unless @rotation.status == :partial

      @rotation.finish!(force: true)
      redirect_to settings_key_rotation_path(@rotation), notice: t("key_rotations_controller.activated")
    end

    private

    def set_rotation
      @rotation = KeyRotation.find(params[:id])
    end
  end
end
