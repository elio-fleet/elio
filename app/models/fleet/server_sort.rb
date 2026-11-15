# Order of the fleet list by one of its columns (?sort=, ?dir=): the name,
# or a figure of the last health inventory (load now, memory, fullest disk,
# updates with the security ones first). Figures start with the biggest; a
# server without the figure (no inventory yet) always comes last.
#
#   ServerSort.new("disk", nil).apply(servers) # fullest disk first
class ServerSort
  KEYS = %w[name load memory disk updates].freeze
  DIRECTIONS = %w[asc desc].freeze

  attr_reader :key, :direction

  def initialize(key, direction)
    @key = key.presence_in(KEYS)
    @direction = direction.presence_in(DIRECTIONS) || default_direction(@key)
  end

  def active? = key.present?

  def sorted_by?(column) = key == column.to_s

  # The direction of a click on a column header: the other one on the current column.
  def next_direction(column)
    return default_direction(column) unless sorted_by?(column)

    direction == "asc" ? "desc" : "asc"
  end

  def apply(servers)
    return servers.to_a unless active?
    return servers.sort_by { |server| server.name.downcase }.then { |list| direction == "desc" ? list.reverse : list } if key == "name"

    sign = direction == "desc" ? -1 : 1
    known, unknown = servers.to_a.partition { |server| value(server) }
    known.sort_by { |server| [ *value(server).map { |figure| figure * sign }, server.name.downcase ] } + unknown.sort_by { |server| server.name.downcase }
  end

  private

  def default_direction(column) = column.to_s == "name" ? "asc" : "desc"

  # The figures to compare, nil when unknown.
  def value(server)
    health = server.inventory(:health)&.data || {}
    figures = case key
    when "load" then [ health["load_percent"] ]
    when "memory" then [ health.dig("memory", "used_percent") ]
    when "disk" then [ health["disk_max_percent"] ]
    when "updates" then [ health.dig("updates", "security").to_i, health.dig("updates", "total").to_i ] if health["updates"]
    end
    figures.map(&:to_f) if figures&.first
  end
end
