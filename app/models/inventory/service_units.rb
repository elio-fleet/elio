# The systemd units of the Services tab, in the order they are read: failed,
# active, enabled at boot but stopped, other inactive ones. Filtered by state
# (?state=) and by a search on the name or the description (?q=); the counts
# of the filters follow the search.
#
#   units = Inventory::ServiceUnits.new(server, state: "inactive", query: "nginx")
#   units.stopped # => the matching units enabled at boot but not running
class Inventory::ServiceUnits
  STATES = %w[active failed inactive].freeze

  attr_reader :state, :query, :failed_units

  def initialize(server, state: nil, query: nil)
    snapshot = server.inventory("services")
    @all = snapshot&.collected? ? Array(snapshot.data["units"]) : []
    @failed_units = Inventory::FailedUnits.new(server)
    @state = state.presence_in(STATES)
    @query = query.to_s.squish.presence
  end

  # A unit that starts at boot and is not running: stopped by hand, or exited.
  # Not a one-shot task, which stops once done (unknown type: an inventory
  # read before the type was).
  def self.stopped?(unit)
    unit["active"] == "inactive" && unit["enabled"] == "enabled" && unit["type"].present? && unit["type"] != "oneshot"
  end

  def failed = shown?("failed") ? matching(@failed_units.units) : []

  def active = shown?("active") ? matching(@all.select { |unit| unit["active"] == "active" }) : []

  def stopped = shown?("inactive") ? inactive.select { |unit| self.class.stopped?(unit) } : []

  def other_inactive = shown?("inactive") ? inactive.reject { |unit| self.class.stopped?(unit) } : []

  # Count per filter (nil: all), within the search.
  def count(state = nil)
    { "failed" => matching(@failed_units.units).size, "active" => matching(@all.select { |unit| unit["active"] == "active" }).size,
      "inactive" => inactive.size }.then { |counts| state ? counts.fetch(state) : counts.values.sum }
  end

  def filtered? = state.present? || query.present?

  def any? = (failed + active + stopped + other_inactive).any?

  private

  def shown?(kind) = state.nil? || state == kind

  def inactive = matching(@all.reject { |unit| unit["active"].in?(%w[failed active]) })

  def matching(units)
    return units unless query

    needle = query.downcase
    units.select { |unit| unit["name"].to_s.downcase.include?(needle) || unit["description"].to_s.downcase.include?(needle) }
  end
end
