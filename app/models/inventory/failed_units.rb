# The failed systemd units of a server, for the Services tab and its count:
# those of the services inventory, and those seen by the health reading, which
# runs more often and lists every kind of unit (mount, socket…). The health
# reading also says since when a unit failed, and whether it failed while the
# server was starting ("at_boot") rather than later on.
#
#   Inventory::FailedUnits.new(server).units # => [{ "name", "active", "description", "since", "at_boot", "seen_at" }]
class Inventory::FailedUnits
  # A unit that failed this soon after the boot failed while the server started.
  BOOT_WINDOW = 10.minutes

  def initialize(server)
    @services = server.inventory("services")
    @health = server.inventory("health")
    @os = server.inventory("os")
  end

  # The units of the services inventory first (with since when, if the health
  # reading knows), then those only the health reading saw (with when it saw them).
  def units
    @units ||= begin
      listed = service_units.select { |unit| unit["active"] == "failed" }.map { |unit| with_boot(unit.merge(details.fetch(unit["name"], {}).slice("since"))) }
      listed + health_only.reject { |unit| listed.any? { |other| other["name"] == unit["name"] } }
    end
  end

  # Only those the health reading saw and the services inventory does not list.
  def health_only
    @health_only ||= Array(health_data["failed_units"]).map do |name|
      with_boot({ "name" => name, "active" => "failed", "description" => details.dig(name, "description"), "since" => details.dig(name, "since"), "seen_at" => @health.collected_at })
    end
  end

  def count = units.size

  def names = units.map { |unit| unit["name"] }

  private

  def service_units = @services&.collected? ? Array(@services.data["units"]) : []

  def health_data = @health&.collected? ? @health.data : {}

  # A boot time older than the failure, from the system inventory: when the
  # server rebooted since that inventory, the old boot time makes the unit
  # look failed later on, never the other way round.
  def with_boot(unit)
    since = Time.zone.parse(unit["since"].to_s) if unit["since"]
    return unit unless since && booted_at && since >= booted_at

    unit.merge("at_boot" => since - booted_at <= BOOT_WINDOW)
  end

  def booted_at
    return @booted_at if defined?(@booted_at)

    @booted_at = (Time.zone.parse(@os.data["booted_at"].to_s) if @os&.collected? && @os.data["booted_at"])
  end

  def details
    @details ||= Array(health_data["failed_units_details"]).index_by { |detail| detail["name"] }
  end
end
