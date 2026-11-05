# Reads the A, AAAA and CNAME records of the zones (all, or those chosen in
# the settings), replaces the stored ones, attaches them to the servers and
# logs the records that point outside the fleet (once each, when the alert
# is on). Returns a summary.
class Integrations::Technitium::Sync
  Record = Data.define(:zone, :name, :record_type, :value, :ttl, :disabled)
  Match = Data.define(:server, :matched_by, :address)

  def initialize(integration, client)
    @integration = integration
    @client = client
  end

  def call
    records = fetch
    servers = Server.includes(:inventory_snapshots).order(:name).to_a
    matches = match(records, servers)

    TechnitiumRecord.transaction do
      existing = TechnitiumRecord.all.index_by { |record| [ record.zone, record.name, record.record_type, record.value ] }
      kept = records.map do |record|
        stored = existing[[ record.zone, record.name, record.record_type, record.value ]] ||
                 TechnitiumRecord.new(zone: record.zone, name: record.name, record_type: record.record_type, value: record.value)
        found = matches[record]
        stored.update!(ttl: record.ttl, disabled: record.disabled, server: found&.server, matched_by: found&.matched_by, matched_address: found&.address)
        stored.id
      end
      TechnitiumRecord.where.not(id: kept).delete_all
    end

    log_outside_fleet
    servers.each(&:refresh_health!)
    I18n.t("integrations.technitium.sync.summary", zones: I18n.t("integrations.technitium.sync.zones", count: @zone_count),
                                                    records: I18n.t("integrations.technitium.sync.records", count: records.size),
                                                    unattached: I18n.t("integrations.technitium.sync.unattached", count: TechnitiumRecord.unattached.count))
  end

  private

  def fetch
    wanted = Array(@integration.value(:zones)).map { |zone| zone.to_s.downcase.chomp(".") }
    zones = @client.zones.reject { |zone| zone["internal"] }.map { |zone| zone["name"].to_s.downcase }
    zones &= wanted if wanted.any?
    @zone_count = zones.size
    zones.flat_map do |zone|
      @client.records(zone).filter_map do |record|
        type = record["type"]
        next unless type.in?(TechnitiumRecord::TYPES)

        value = type == "CNAME" ? record.dig("rData", "cname") : record.dig("rData", "ipAddress")
        next if value.blank?

        Record.new(zone: zone, name: record["name"].to_s.downcase, record_type: type, value: value.to_s.downcase.chomp("."), ttl: record["ttl"], disabled: record["disabled"] == true)
      end
    end
  end

  # A manual link (per name) first, then the server with the IP, then for a
  # CNAME the record or the host it points to.
  def match(records, servers)
    directory = ServerDirectory.new(servers)
    by_id = servers.index_by(&:id)
    links = @integration.links.to_h { |link| [ link.external_id, link.server_id ] }
    matches = records.to_h do |record|
      if links.key?(record.name)
        server = by_id[links[record.name]]
        next [ record, server && Match.new(server, "manual", nil) ]
      end
      found = record.record_type != "CNAME" && directory.by_address(record.value)
      [ record, found ? Match.new(found.server, "address", found.address) : nil ]
    end
    by_name = records.each_with_object({}) { |record, names| names[record.name] ||= matches[record] if matches[record] }
    records.each do |record|
      next unless record.record_type == "CNAME" && matches[record].nil? && !links.key?(record.name)

      server = by_name[record.value]&.server || directory.by_host(record.value, names: true)
      matches[record] = Match.new(server, "cname", nil) if server
    end
    matches
  end

  def log_outside_fleet
    state = @integration.state.dup
    outside = TechnitiumRecord.outside_fleet.order(:name).to_a
    keys = outside.map { |record| "#{record.name} #{record.value}" }
    known = state["outside"]
    unless known.nil?
      outside.reject { |record| known.include?("#{record.name} #{record.value}") }.each do |record|
        Activity.record!(:dns_record_outside_fleet, user: nil, record: record.name, target: record.value) if @integration.value(:alert_outside)
      end
    end
    state["outside"] = keys
    @integration.update_columns(state: state)
  end
end
