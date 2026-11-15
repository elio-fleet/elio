# A DNS record (A, AAAA or CNAME) of the fleet's DNS, read from a source: the
# OVHcloud extension (source "ovh"), Technitium DNS ("technitium"), Gandi
# ("gandi") or a manual source ("manual:<connection id>", Integrations::ManualDns). Every
# source is attached to the servers the same way (Dns::Matcher): a manual
# link by name (DnsLink, common to the sources), the IP of an A / AAAA record,
# or, for a CNAME, a name already attached or a server's host name.
class DnsRecord < ApplicationRecord
  TYPES = %w[A AAAA CNAME].freeze
  SOURCES = { "ovh" => "OVHcloud", "technitium" => "Technitium", "gandi" => "Gandi" }.freeze

  belongs_to :server, optional: true

  # Only the records of the enabled sources are read (page, tabs, attachments,
  # alerts, search): a disabled extension leaves no trace, its records stay in
  # the table for when it is enabled again. Dns::Store writes through unscoped.
  default_scope { where(source: Dns.active_source_keys) }

  scope :attached, -> { where.not(server_id: nil) }
  scope :unattached, -> { where(server_id: nil) }
  scope :addresses, -> { where(record_type: %w[A AAAA]) }
  scope :of_source, ->(source) { where(source: source.to_s) }
  # A / AAAA records whose IP belongs to no server of the fleet.
  scope :outside_fleet, -> { addresses.unattached.where(disabled: false) }

  # Names whose records differ between two sources (split horizon: a public
  # IP at OVH, a private one in Technitium) — the same records do not count.
  def self.conflicting_names
    per_source = select(:name, :source, Arel.sql("string_agg(record_type || ' ' || value, ',' ORDER BY record_type, value) AS records")).group(:name, :source)
    unscoped.from(per_source, :per_source).group(:name).having("COUNT(*) > 1 AND COUNT(DISTINCT records) > 1").pluck(:name)
  end

  scope :conflicting, -> { where(name: conflicting_names) }

  # Every name that leads to an IP: its A / AAAA records, then the CNAMEs to
  # one of these names (a few levels, as Dns::Matcher), sorted. nil when
  # the text is not an IP. IPv6 compared in its short form.
  def self.names_pointing_to(text)
    return if text.to_s.include?("/") || text.blank?

    ip = IPAddr.new(text.to_s.strip)
    values = [ text.to_s.strip.downcase, ip.to_s ].uniq
    names = addresses.where(value: values).distinct.pluck(:name)
    Dns::Matcher::CNAME_PASSES.times do
      found = where(record_type: "CNAME", value: names).where.not(name: names).distinct.pluck(:name)
      break if found.empty?

      names += found
    end
    names.sort
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    nil
  end

  def self.source_label(source)
    return Integrations::ManualDns.source_label(source) if manual_source?(source)

    SOURCES.fetch(source.to_s, source.to_s)
  end

  def self.manual_source?(source) = source.to_s.start_with?(Integrations::ManualDns::SOURCE_PREFIX)

  def source_label = self.class.source_label(source)

  def address? = record_type.in?(%w[A AAAA])

  def manual? = matched_by == "manual"

  def matched_label = matched_by.presence && I18n.t("dns_record.matches.#{matched_by}", address: matched_address, default: "")
end
