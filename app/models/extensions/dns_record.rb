# A DNS record (A, AAAA or CNAME) of the fleet's DNS, read from a source: the
# OVHcloud extension (source "ovh") or Technitium DNS ("technitium"). Every
# source is attached to the servers the same way (Dns::Matcher): a manual
# link by name (DnsLink, common to the sources), the IP of an A / AAAA record,
# or, for a CNAME, a name already attached or a server's host name.
class DnsRecord < ApplicationRecord
  TYPES = %w[A AAAA CNAME].freeze
  SOURCES = { "ovh" => "OVHcloud", "technitium" => "Technitium" }.freeze

  belongs_to :server, optional: true

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

  def self.source_label(source) = SOURCES.fetch(source.to_s, source.to_s)

  def source_label = self.class.source_label(source)

  def address? = record_type.in?(%w[A AAAA])

  def manual? = matched_by == "manual"

  def matched_label = matched_by.presence && I18n.t("dns_record.matches.#{matched_by}", address: matched_address, default: "")
end
