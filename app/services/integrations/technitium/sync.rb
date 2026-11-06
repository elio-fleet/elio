# Reads the A, AAAA and CNAME records of the zones (all, or those chosen in
# the settings) and hands them to the fleet's DNS (Dns::Store, source
# "technitium"), which attaches them to the servers. Logs the records that
# point outside the fleet (once each, when the alert is on). Returns a summary.
class Integrations::Technitium::Sync
  SOURCE = "technitium".freeze

  def initialize(integration, client)
    @integration = integration
    @client = client
  end

  def call
    count = Dns::Store.replace(SOURCE, fetch)
    log_outside_fleet
    I18n.t("integrations.technitium.sync.summary", zones: I18n.t("integrations.technitium.sync.zones", count: @zone_count),
                                                    records: I18n.t("integrations.technitium.sync.records", count: count),
                                                    unattached: I18n.t("integrations.technitium.sync.unattached", count: DnsRecord.of_source(SOURCE).unattached.count))
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
        next unless type.in?(DnsRecord::TYPES)

        value = type == "CNAME" ? record.dig("rData", "cname") : record.dig("rData", "ipAddress")
        { zone: zone, name: record["name"], record_type: type, value: value, ttl: record["ttl"], disabled: record["disabled"] == true } if value.present?
      end
    end
  end

  def log_outside_fleet
    state = @integration.state.dup
    outside = DnsRecord.of_source(SOURCE).outside_fleet.order(:name).to_a
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
