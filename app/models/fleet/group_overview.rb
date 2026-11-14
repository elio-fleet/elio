# The groups on the overview, each with its servers most serious first
# (unreachable, critical, to watch, then by name) and how many need handling.
# Servers must come with their groups loaded.
class GroupOverview
  ORDER = %w[off crit warn].freeze

  Row = Data.define(:group, :servers) do
    def critical = servers.count { |server| %w[crit off].include?(server.health_state) }
    def to_watch = servers.count { |server| server.health_state == "warn" }
  end

  attr_reader :rows

  def initialize(groups, servers)
    @rows = groups.map do |group|
      members = servers.select { |server| server.server_groups.include?(group) }
      Row.new(group, members.sort_by { |server| [ ORDER.index(server.health_state) || ORDER.size, server.name.downcase ] })
    end
  end

  def any? = rows.any?
end
