# Reads the A, AAAA and CNAME records of the zones (all, or those chosen in
# the settings) and hands them to the fleet's DNS (Dns::Store, source
# "technitium"), which attaches them to the servers and raises the DNS alerts
# (Dns::Alerts). Returns a summary.
class Integrations::Technitium::Sync
  SOURCE = "technitium".freeze

  def initialize(integration, client)
    @integration = integration
    @client = client
  end

  def call
    count = Dns::Store.replace(SOURCE, fetch)
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
end
