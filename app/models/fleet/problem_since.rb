# Since when each problem of the "To handle" lists has been there, read from
# the journal (nothing new is stored): the last server_unreachable or
# ssh_access_lost of a server, and for a health or Docker reason the first
# event of the current run of problems (since the last recovery) that names
# it, or else the start of that run. nil when the journal has nothing (first
# evaluation, events purged). A few queries for the whole fleet, made only
# when asked.
class ProblemSince
  # Events that open or extend a run of problems, and the one that ends it.
  RUNS = { health: [ %w[health_warning health_critical], "health_recovered" ],
           docker: [ %w[docker_warning docker_critical], "docker_recovered" ] }.freeze

  LOSSES = %w[server_unreachable ssh_access_lost].freeze

  def initialize(servers)
    @ids = servers.map(&:id)
  end

  def unreachable(server) = losses[[ server.id, "server_unreachable" ]]

  def key_refused(server) = losses[[ server.id, "ssh_access_lost" ]]

  # A reason of server.health_reasons (family :health) or docker_reasons (:docker).
  def reason(server, reason, family)
    events = runs(family)[server.id]
    return if events.blank?

    identity = Inventory::HealthStatus.identity(reason)
    named = events.find { |_, reasons| reasons.any? { |logged| Inventory::HealthStatus.identity(logged) == identity } }
    (named || events.first).first
  end

  private

  def losses
    @losses ||= Activity.where(server_id: @ids, kind: LOSSES).group(:server_id, :kind).maximum(:created_at)
  end

  # { server_id => [[created_at, reasons], …] } oldest first, after the last recovery.
  def runs(family)
    @runs ||= {}
    @runs[family] ||= begin
      kinds, recovery = RUNS.fetch(family)
      Activity.where(server_id: @ids, kind: kinds)
              .where("activities.created_at > COALESCE((SELECT MAX(ended.created_at) FROM activities ended " \
                     "WHERE ended.server_id = activities.server_id AND ended.kind = ?), '-infinity')", recovery)
              .order(:created_at, :id).pluck(:server_id, :created_at, Arel.sql("activities.data -> 'reasons'"))
              .group_by(&:first).transform_values { |rows| rows.map { |_, at, reasons| [ at, Array(reasons) ] } }
    end
  end
end
