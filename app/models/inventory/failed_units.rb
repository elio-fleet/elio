# The failed systemd units of a server, for the Services tab and its count:
# those of the services inventory, and those seen by the health reading, which
# runs more often and lists every kind of unit (mount, socket…). The health
# reading also says since when a unit failed.
#
#   Inventory::FailedUnits.new(server).units # => [{ "name", "active", "description", "since", "seen_at" }]
class Inventory::FailedUnits
  def initialize(server)
    @services = server.inventory("services")
    @health = server.inventory("health")
  end

  # The units of the services inventory first (with since when, if the health
  # reading knows), then those only the health reading saw (with when it saw them).
  def units
    @units ||= begin
      listed = service_units.select { |unit| unit["active"] == "failed" }.map { |unit| unit.merge(details.fetch(unit["name"], {}).slice("since")) }
      listed + health_only.reject { |unit| listed.any? { |other| other["name"] == unit["name"] } }
    end
  end

  # Only those the health reading saw and the services inventory does not list.
  def health_only
    @health_only ||= Array(health_data["failed_units"]).map do |name|
      { "name" => name, "active" => "failed", "description" => details.dig(name, "description"), "since" => details.dig(name, "since"), "seen_at" => @health.collected_at }
    end
  end

  def count = units.size

  private

  def service_units = @services&.collected? ? Array(@services.data["units"]) : []

  def health_data = @health&.collected? ? @health.data : {}

  def details
    @details ||= Array(health_data["failed_units_details"]).index_by { |detail| detail["name"] }
  end
end
