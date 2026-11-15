# State of Docker on a server, apart from the health of the server itself
# (Inventory::HealthStatus): crit when containers are unhealthy, restart in
# a loop, or are expected (Server#expected_containers) but not running, warn for serious fixable CVEs in the images or images to update, ok
# otherwise; nil without a readable Docker. The alerts of Settings → Docker
# choose which reasons count. Reasons are stored like the health ones (key +
# parameters, Inventory::HealthStatus::Reason) and recomputed with them
# (Server#refresh_health!, Inventory::HealthStatus::VERSION). Just after the
# host booted (Inventory::Collectors::Docker::BOOT_GRACE), containers are still
# starting: none counts as unhealthy or missing yet.
class Inventory::DockerStatus
  Result = Inventory::HealthStatus::Result
  # Containers named in a reason about several; the others are "…".
  NAMED = 5

  def self.evaluate(server, settings: AppSetting.current) = new(server, settings).evaluate

  def initialize(server, settings)
    @server = server
    @settings = settings
    @docker = server.inventory("docker")
  end

  def evaluate
    return Result.new(state: nil, reasons: []) unless @docker&.collected? && @docker.data["docker"] == "ok"

    reasons = [ *container_reasons, *vulnerability_reasons, *update_reasons ]
    state = if reasons.any? { |reason| reason.tone == "crit" } then "crit"
    elsif reasons.any? then "warn"
    else "ok"
    end
    Result.new(state: state, reasons: reasons)
  end

  private

  def reason(...) = Inventory::HealthStatus.reason(...)

  def containers = Array(@docker.data["containers"])

  def container_reasons
    return [] if starting_up?

    [ (grouped(containers.select { |container| container["looping"] }.pluck("name"), :looping) if @settings.docker_alert_restarts),
      (grouped(containers.select { |container| container["health"] == "unhealthy" }.pluck("name"), :unhealthy) if @settings.docker_alert_unhealthy),
      grouped(missing_containers, :missing) ].compact
  end

  # Expected containers that do not run: absent, stopped or paused (one
  # restarting is already a loop).
  def missing_containers
    present = containers.select { |container| container["state"].in?(%w[running restarting]) }.pluck("name")
    @server.expected_container_names - present
  end

  # One container by its name, several by their count and their first names
  # (`containers`, a detail: the same problem when one more fails).
  def grouped(names, state)
    return if names.empty?
    return reason("crit", :"container_#{state}", name: names.first) if names.one?

    reason("crit", :"containers_#{state}", count: names.size, containers: names.first(NAMED) + (names.size > NAMED ? [ "…" ] : []))
  end

  def starting_up?
    booted_at = Time.zone.parse(@docker.data["booted_at"].to_s)
    Inventory::Collectors::Docker.starting_up?(booted_at, @docker.collected_at)
  end

  # Fixable CVEs of the images from the alert severity of the settings: fixed
  # by updating the image, not the server.
  def vulnerability_reasons
    minimum = @settings.vulnerability_alert_severity
    return [] if minimum == "none" || !@settings.docker_alert_vulnerabilities

    serious = @server.server_vulnerabilities.images.fixable.at_least(minimum)
    count = serious.distinct.count(:cve)
    count.positive? ? [ reason("warn", :image_vulnerabilities, count: count, images: serious.distinct.count(:image)) ] : []
  end

  def update_reasons
    return [] unless @settings.docker_alert_updates

    images = Array(@docker.data["images"]).select { |image| image["used"] }
    updates = ImageUpdate.for_images(images)
    count = images.count { |image| ImageUpdate.state_for(image, updates) == :available }
    count.positive? ? [ reason("warn", :images_to_update, count: count) ] : []
  end
end
