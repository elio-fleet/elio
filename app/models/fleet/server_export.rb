require "csv"

# The fleet list as CSV, with the filters and the order of the page and
# without its pagination: one line per server, its address, system, health
# and the figures of its last inventory. Column names are stable English
# keys (a script can read them); the health reasons are in the user's
# language. Cells that a spreadsheet would run as a formula are neutralised
# (CsvCell).
#
#   ServerExport.new(servers).to_csv
class ServerExport
  HEADERS = %w[name host port username groups hostname addresses os state reasons docker load_percent memory_percent disk_percent
               updates security_updates inventoried_at last_checked_at].freeze

  def initialize(servers)
    @servers = servers
  end

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      @servers.each { |server| csv << row(server).map { |value| CsvCell.safe(value) } }
    end
  end

  def filename = "elio-servers-#{Date.current.iso8601}.csv"

  private

  def row(server)
    health = server.inventory(:health)&.data || {}
    [ server.name, server.host, server.port, server.username, server.server_groups.map(&:name).join(", "), server.hostname,
      server.addresses.join(" "), server.os_name, server.health_state, server.health_reason_texts.join(" · "), server.docker_status,
      health["load_percent"], health.dig("memory", "used_percent"), health["disk_max_percent"],
      health.dig("updates", "total"), health.dig("updates", "security"), server.inventoried_at&.iso8601, server.last_checked_at&.iso8601 ]
  end
end
