# Writes the records read by one DNS source (OVHcloud, Technitium): its
# previous records are replaced, the others are left alone, then every record
# is attached again (Dns::Matcher), since a record of one source can change
# the attachment of another (a CNAME to a name of the other source).
#
#   Dns::Store.replace("technitium", [ { zone:, name:, record_type:, value:, ttl:, disabled:, source_id: } ])
module Dns::Store
  def self.replace(source, records)
    now = Time.current
    rows = records.filter_map do |record|
      type = record[:record_type].to_s.upcase
      value = record[:value].to_s.strip.downcase.chomp(".")
      name = record[:name].to_s.strip.downcase.chomp(".")
      next unless type.in?(DnsRecord::TYPES) && value.present? && name.present?

      { source: source.to_s, source_id: record[:source_id] || [ record[:zone], name, type, value ].join("|"), zone: record[:zone].to_s.downcase,
        name: name, record_type: type, value: value, ttl: record[:ttl], disabled: record[:disabled] == true, created_at: now, updated_at: now }
    end.uniq { |row| row[:source_id] }

    DnsRecord.transaction do
      DnsRecord.unscoped.of_source(source).where.not(source_id: rows.map { |row| row[:source_id] }).delete_all
      DnsRecord.upsert_all(rows, unique_by: %i[source source_id], update_only: %i[zone name record_type value ttl disabled]) if rows.any?
    end
    servers = Dns::Matcher.call
    Server.refresh_extension_health!(servers)
    Dns::Alerts.call
    rows.size
  end

  # Deletes the records of a source and forgets the alerts they raised: its
  # next records are a first sync again (nothing logged for what is there).
  def self.forget(source)
    replace(source, [])
    settings = AppSetting.current
    outside = settings.dns_alert_state["outside"]
    settings.update_columns(dns_alert_state: settings.dns_alert_state.merge("outside" => outside.except(source.to_s))) if outside.is_a?(Hash)
  end
end
