require "csv"

# The pending security updates of the fleet, for a spreadsheet: one line per
# server and package, read with one pluck. Column names are stable English
# keys, like the vulnerabilities export.
#
#   Inventory::SecurityUpdateExport.new(Inventory::Package.security).to_csv
class Inventory::SecurityUpdateExport
  COLUMNS = {
    "server" => "servers.name",
    "package" => "inventory_packages.name",
    "installed_version" => "inventory_packages.version",
    "available_version" => "inventory_packages.available_version",
    "origin" => "inventory_packages.origin"
  }.freeze

  def initialize(scope)
    @scope = scope
  end

  def records
    @records ||= @scope.joins(:server).order("servers.name", "inventory_packages.name")
                       .pluck(*COLUMNS.values.map { |column| Arel.sql(column) })
                       .map { |values| COLUMNS.keys.zip(values).to_h }
                       .map { |record| record.merge("reboot" => record["package"].match?(Inventory::Package::REBOOT)) }
  end

  def to_csv
    CSV.generate do |csv|
      csv << headers
      records.each { |record| csv << headers.map { |key| CsvCell.safe(record[key]) } }
    end
  end

  def filename = "elio-security-updates-#{Date.current.iso8601}.csv"

  private

  def headers = COLUMNS.keys + [ "reboot" ]
end
