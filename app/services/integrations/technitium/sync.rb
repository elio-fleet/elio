# Reads the A, AAAA and CNAME records of the zones (all, or those chosen in
# the settings) and hands them to the fleet's DNS (Dns::Store, source
# "technitium"), which attaches them to the servers and raises the DNS alerts
# (Dns::Alerts). Returns a summary.
#
# A zone that cannot be read is remembered in integration.state
# ("unreadable_zones": [{ "zone", "reason", "message" }], shown in the
# settings) instead of silently missing:
# - "not_visible": chosen in the settings, but not in the zones the token
#   sees (a typo, a deleted zone, or no View permission on it);
# - "refused": listed, but reading its records failed; its previous records
#   are kept, so that one refused zone does not delete its names and raise
#   the DNS alerts. When every zone is refused, the sync fails.
class Integrations::Technitium::Sync
  SOURCE = "technitium".freeze

  def initialize(integration, client)
    @integration = integration
    @client = client
  end

  def call
    count = Dns::Store.replace(SOURCE, fetch)
    @integration.update_columns(state: @integration.state.merge("unreadable_zones" => @unreadable))
    summary = I18n.t("integrations.technitium.sync.summary", zones: I18n.t("integrations.technitium.sync.zones", count: @zone_count),
                                                              records: I18n.t("integrations.technitium.sync.records", count: count),
                                                              unattached: I18n.t("integrations.technitium.sync.unattached", count: DnsRecord.of_source(SOURCE).unattached.count))
    summary += I18n.t("integrations.technitium.sync.unreadable", count: @unreadable.size, zones: @unreadable.pluck("zone").join(", ")) if @unreadable.any?
    summary
  end

  private

  def fetch
    wanted = Integrations::Technitium.wanted_zones(@integration)
    visible = @client.zones.reject { |zone| zone["internal"] }.map { |zone| zone["name"].to_s.downcase }
    zones = wanted.any? ? visible & wanted : visible
    @zone_count = zones.size
    @unreadable = (wanted - visible).map { |zone| { "zone" => zone, "reason" => "not_visible" } }
    errors = []
    records = zones.flat_map do |zone|
      read(zone)
    rescue Integrations::Error => e
      errors << e
      @unreadable << { "zone" => zone, "reason" => "refused", "message" => e.message }
      previous(zone)
    end
    raise errors.first if errors.any? && errors.size == zones.size

    records
  end

  def read(zone)
    @client.records(zone).filter_map do |record|
      type = record["type"]
      next unless type.in?(DnsRecord::TYPES)

      value = type == "CNAME" ? record.dig("rData", "cname") : record.dig("rData", "ipAddress")
      { zone: zone, name: record["name"], record_type: type, value: value, ttl: record["ttl"], disabled: record["disabled"] == true } if value.present?
    end
  end

  # The records stored for the zone at the last sync that could read it.
  def previous(zone)
    DnsRecord.unscoped.of_source(SOURCE).where(zone: zone).map do |record|
      { source_id: record.source_id, zone: zone, name: record.name, record_type: record.record_type, value: record.value, ttl: record.ttl, disabled: record.disabled }
    end
  end
end
