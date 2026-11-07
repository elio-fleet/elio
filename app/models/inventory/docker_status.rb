# State of Docker on a server, apart from the health of the server itself
# (Inventory::HealthStatus): crit when containers are unhealthy or restart in
# a loop, warn for serious fixable CVEs in the images or images to update, ok
# otherwise; nil without a readable Docker. The alerts of Settings → Docker
# choose which reasons count. Reasons are stored like the health ones (key +
# parameters, Inventory::HealthStatus::Reason) and recomputed with them
# (Server#refresh_health!, Inventory::HealthStatus::VERSION).
class Inventory::DockerStatus
  Result = Inventory::HealthStatus::Result

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
    [ (grouped(containers.select { |container| container["looping"] }, :looping) if @settings.docker_alert_restarts),
      (grouped(containers.select { |container| container["health"] == "unhealthy" }, :unhealthy) if @settings.docker_alert_unhealthy) ].compact
  end

  def grouped(list, state)
    return if list.empty?

    list.one? ? reason("crit", :"container_#{state}", name: list.first["name"]) : reason("crit", :"containers_#{state}", count: list.size)
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
