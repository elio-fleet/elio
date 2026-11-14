# A server whose host key changed and waits for an administrator: its last
# host key activity is host_key_mismatch, and no SSH check has succeeded since.
# Listed on the host keys page (HostKeyBatchesController) to accept several at once.
PendingHostKey = Data.define(:server, :activity) do
  def self.all
    latest = Activity.where(kind: %w[host_key_mismatch host_key_changed]).where.not(server_id: nil)
                     .select("DISTINCT ON (activities.server_id) activities.*").order(:server_id, id: :desc)
    Activity.from(latest, :activities).where(kind: "host_key_mismatch").includes(:server).order(:id)
            .map { |activity| new(server: activity.server, activity: activity) }
            .reject(&:resolved?)
  end

  def new_fingerprint = activity.data["new_fingerprint"]
  def key_type = activity.data["key_type"]
  def new_algorithm? = activity.data["new_algorithm"] == true
  def detected_at = activity.created_at

  # The keys Elio still pins for the server (Ssh::KnownHosts::Entry).
  def known = Ssh::KnownHosts.entries(server.host, server.port)

  # The server answered an SSH check after the change (its old key came back).
  def resolved?
    server.ssh_ok == true && server.ssh_checked_at.present? && server.ssh_checked_at > activity.created_at
  end
end
