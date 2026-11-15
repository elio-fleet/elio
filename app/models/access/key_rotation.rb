# Replaces Elio's key without cutting the access to servers (RotateSshKeyJob):
# a pending key is installed on each server with the old key, checked, then the
# old key is removed with the new one. Once every server is done (or when
# forced), the new key becomes the active one and the old key is deleted.
# Meanwhile connections try both keys (SshKey.app_keys).
class KeyRotation < ApplicationRecord
  class AlreadyRunning < StandardError; end

  # Longer than one server can take (connection and command time limits of
  # the install, the check and the removal): a running rotation that has not
  # moved for that long has lost its job (Elio restarted, worker killed).
  STALLED_AFTER = 15.minutes

  belongs_to :old_key, class_name: "SshKey", optional: true
  belongs_to :new_key, class_name: "SshKey", optional: true
  belongs_to :started_by, class_name: "User", optional: true
  has_many :steps, -> { order(:server_name) }, class_name: "KeyRotationStep", dependent: :delete_all

  def self.in_progress = where(activated_at: nil).order(:created_at).last

  def self.start!(by:)
    raise AlreadyRunning if SshKey.pending.exists?

    transaction do
      create!(old_key: SshKey.current, new_key: SshKey.generate_pending!, started_by: by, servers_count: Server.count)
    end
  end

  def running? = finished_at.nil?

  def stalled? = running? && updated_at < STALLED_AFTER.ago

  def activated? = activated_at.present?

  def servers_done = steps.count

  def failed_count = steps.failed.count

  def status
    if activated? then :activated
    elsif running? then :running
    else :partial
    end
  end

  # Closes a run: activates the new key when every server succeeded, or when
  # forced (the failed servers then lose Elio's access).
  def finish!(force: false)
    update!(finished_at: Time.current, forced: force)
    activate! if force || failed_count.zero?
  end

  private

  def activate!
    transaction do
      old_key&.destroy!
      new_key.update!(state: :active)
      update!(activated_at: Time.current)
    end
    Activity.record!(:ssh_key_rotated, fingerprint: new_key.fingerprint, servers: servers_count, failed: failed_count, forced: forced)
  end
end
