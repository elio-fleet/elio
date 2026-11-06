# Reads the domains (expiry date, auto renewal) and the A, AAAA and CNAME
# records of the domains served by LiveDNS (all, or those chosen in the
# settings), hands the records to the fleet's DNS (Dns::Store, source
# "gandi") and logs the domains about to expire (once each, never on the
# first sync). Returns a summary.
class Integrations::Gandi::Sync
  SOURCE = "gandi".freeze

  def initialize(integration, client)
    @integration = integration
    @client = client
  end

  def call
    wanted = Array(@integration.value(:domains)).map { |domain| domain.to_s.downcase.chomp(".") }
    livedns = @client.livedns_domains.map { |domain| domain["fqdn"].to_s.downcase }
    livedns &= wanted if wanted.any?
    count = Dns::Store.replace(SOURCE, livedns.flat_map { |fqdn| records(fqdn) })
    domains_read = read_domains(livedns, wanted)
    summary = I18n.t("integrations.gandi.sync.summary", domains: I18n.t("integrations.gandi.sync.domains", count: livedns.size),
                                                         records: I18n.t("integrations.gandi.sync.records", count: count),
                                                         unattached: I18n.t("integrations.gandi.sync.unattached", count: DnsRecord.of_source(SOURCE).unattached.count))
    domains_read ? summary : summary + I18n.t("integrations.gandi.sync.no_domains", message: @domains_error)
  end

  private

  # The domains and their expiry: optional (another right of the token than
  # LiveDNS), so their failure leaves the DNS sync done and the previous list.
  def read_domains(livedns, wanted)
    domains = @client.domains.map { |domain| domain_row(domain, livedns) }
    domains.select! { |domain| wanted.include?(domain["fqdn"]) } if wanted.any?
    @integration.update_columns(state: @integration.state.merge("domains" => domains))
    log_expiring
    true
  rescue Integrations::Error => e
    @domains_error = e.message
    false
  end

  def domain_row(domain, livedns)
    fqdn = domain["fqdn"].to_s.downcase
    { "fqdn" => fqdn, "expires_at" => domain.dig("dates", "registry_ends_at"), "autorenew" => autorenew?(domain["autorenew"]),
      "livedns" => livedns.include?(fqdn) || domain.dig("nameserver", "current") == "livedns" }
  end

  # A boolean in the list of domains, an object ({ "enabled" }) in the details of one.
  def autorenew?(value) = value.is_a?(Hash) ? value["enabled"] == true : value == true

  # "@" is the domain itself; a CNAME without a final dot is relative to the domain.
  def records(fqdn)
    @client.records(fqdn).flat_map do |rrset|
      type = rrset["rrset_type"].to_s.upcase
      next [] unless type.in?(DnsRecord::TYPES)

      name = rrset["rrset_name"].to_s == "@" ? fqdn : "#{rrset["rrset_name"]}.#{fqdn}"
      Array(rrset["rrset_values"]).map do |value|
        value = value.to_s
        value = value == "@" ? fqdn : "#{value}.#{fqdn}" if type == "CNAME" && !value.end_with?(".")
        { zone: fqdn, name: name, record_type: type, value: value, ttl: rrset["rrset_ttl"] }
      end
    end
  end

  # Each domain once, until it is renewed; nothing on the first sync.
  def log_expiring
    expiring = Integrations::Gandi.expiring_domains(@integration)
    state = @integration.state.dup
    known = state["expiring"]
    keys = expiring.map { |domain| domain["fqdn"] }
    if known && @integration.value(:alert_expiring)
      expiring.reject { |domain| known.include?(domain["fqdn"]) }.each do |domain|
        days = ((Time.zone.parse(domain["expires_at"]) - Time.current) / 1.day).ceil
        Activity.record!(:gandi_domain_expiring, user: nil, domain: domain["fqdn"], days: days)
      end
    end
    state["expiring"] = keys
    @integration.update_columns(state: state)
  end
end
