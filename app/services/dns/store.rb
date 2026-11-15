# Writes the records read by one DNS source (OVHcloud, Technitium): its
# previous records are replaced, the others are left alone, then every record
# is attached again (Dns::Matcher), since a record of one source can change
# the attachment of another (a CNAME to a name of the other source).
#
# Only the difference is written: the records gone are deleted, the new ones
# inserted, the changed ones updated; an unchanged record keeps its row, its
# id and its updated_at (a synchronization that changes nothing writes
# nothing). Returns the number of records read.
#
#   Dns::Store.replace("technitium", [ { zone:, name:, record_type:, value:, ttl:, disabled:, source_id: } ])
module Dns::Store
  COLUMNS = %i[zone name record_type value ttl disabled].freeze

  def self.replace(source, records)
    rows = records.filter_map do |record|
      type = record[:record_type].to_s.upcase
      value = record[:value].to_s.strip.downcase.chomp(".")
      name = record[:name].to_s.strip.downcase.chomp(".")
      next unless type.in?(DnsRecord::TYPES) && value.present? && name.present?

      { source_id: record[:source_id] || [ record[:zone], name, type, value ].join("|"), zone: record[:zone].to_s.downcase,
        name: name, record_type: type, value: value, ttl: record[:ttl].presence&.to_i, disabled: record[:disabled] == true }
    end.uniq { |row| row[:source_id] }

    DnsRecord.transaction { write(source.to_s, rows) }
    servers = Dns::Matcher.call
    servers.each(&:refresh_health!)
    Dns::Alerts.call
    rows.size
  end

  # The difference with the rows of the source: { deleted:, inserted:, updated: } counts.
  def self.write(source, rows)
    existing = DnsRecord.unscoped.of_source(source).pluck(:source_id, :id, *COLUMNS).to_h { |source_id, id, *values| [ source_id, [ id, COLUMNS.zip(values).to_h ] ] }
    wanted = rows.index_by { |row| row[:source_id] }
    gone = existing.keys - wanted.keys
    DnsRecord.unscoped.where(id: existing.values_at(*gone).map(&:first)).delete_all if gone.any?

    now = Time.current
    new_rows = wanted.except(*existing.keys).values.map { |row| row.merge(source: source, created_at: now, updated_at: now) }
    DnsRecord.unscoped { DnsRecord.insert_all(new_rows) } if new_rows.any?

    changed = wanted.slice(*existing.keys).filter_map do |source_id, row|
      id, values = existing[source_id]
      { id: id, **row.except(:source_id), updated_at: now } if values != row.except(:source_id)
    end
    changed.each { |row| DnsRecord.unscoped.where(id: row[:id]).update_all(row.except(:id)) }
    { deleted: gone.size, inserted: new_rows.size, updated: changed.size }
  end
  private_class_method :write
end
