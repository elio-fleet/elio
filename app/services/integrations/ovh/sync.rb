# Stores the OVHcloud resources (replacing the previous ones), attaches them
# to the servers, logs the alerts enabled in the extension (once each) and
# refreshes the health of the servers. The DNS records go to the fleet's DNS
# (Dns::Store, source "ovh"). Returns a summary.
class Integrations::Ovh::Sync
  def initialize(integration, resources)
    @integration = integration
    @resources = resources
  end

  def call
    dns, @resources = @resources.partition { |resource| resource.kind == "dns_record" }
    Dns::Store.replace("ovh", dns.map { |record| dns_row(record) })

    servers = Server.includes(:inventory_snapshots, :server_groups).order(:name).to_a
    links = @integration.links.to_h { |link| [ link.external_id, link.server_id ] }
    matches = Integrations::Ovh::Matcher.new(servers, manual_links: links).call(@resources)

    OvhResource.transaction do
      existing = OvhResource.all.index_by { |record| [ record.kind, record.external_id ] }
      kept = @resources.map do |resource|
        record = existing[[ resource.kind, resource.external_id ]] || OvhResource.new(kind: resource.kind, external_id: resource.external_id)
        match = matches[resource]
        record.update!(name: resource.name, data: resource.data, addresses: resource.addresses, expires_at: resource.expires_at,
                       server: match&.server, matched_by: match&.matched_by, matched_address: match&.address)
        record.id
      end
      OvhResource.where.not(id: kept).delete_all
    end

    log_alerts
    servers.each(&:refresh_health!)

    counts = OvhResource.group(:kind).count.merge("dns_record" => DnsRecord.of_source("ovh").count.nonzero?).compact
    parts = %w[instance dedicated vps ip dns_record].filter_map { |kind| I18n.t("integrations.ovh.sync.counts.#{kind}", count: counts[kind]) if counts[kind] }
    I18n.t("integrations.ovh.sync.summary", parts: parts.join(", ").presence || I18n.t("integrations.ovh.sync.no_resource"), unattached: I18n.t("integrations.ovh.sync.unattached", count: OvhResource.services.unattached.count))
  end

  private

  def dns_row(record)
    { source_id: record.external_id, zone: record.data["zone"], name: record.name, record_type: record.data["type"], value: record.data["target"], ttl: record.data["ttl"] }
  end

  # Each alert once per resource, until the situation goes away.
  def log_alerts
    state = @integration.state.dup

    expiring = Integrations::Ovh.expiring_services(@integration).to_a
    once(state, "expiring", expiring.map(&:link_key)) do |key|
      resource = expiring.find { |candidate| candidate.link_key == key }
      Activity.record!(:ovh_service_expiring, server: resource.server, user: nil, service: resource.name, days: resource.days_left) if @integration.value(:alert_expiring)
    end

    unmanaged = OvhResource.services.unattached.to_a
    once(state, "unmanaged", unmanaged.map(&:link_key)) do |key|
      service = unmanaged.find { |candidate| candidate.link_key == key }
      Activity.record!(:ovh_service_unmanaged, user: nil, service: service.name, kind_label: service.kind_label) if @integration.value(:alert_unmanaged_service)
    end

    @integration.update_columns(state: state)
  end

  # Yields the keys that were not there at the previous sync (none on the first one).
  def once(state, name, keys)
    known = state[name]
    (keys - Array(known)).each { |key| yield key } unless known.nil?
    state[name] = keys
  end
end
