# A DNS record (A, AAAA or CNAME) of a Technitium DNS Server zone, attached to
# the server it points to (Integrations::Technitium::Sync): by a manual link,
# by the IP of an A / AAAA record, or, for a CNAME, by the record or host
# name it points to.
class TechnitiumRecord < ApplicationRecord
  TYPES = %w[A AAAA CNAME].freeze

  belongs_to :server, optional: true

  scope :attached, -> { where.not(server_id: nil) }
  scope :unattached, -> { where(server_id: nil) }
  scope :addresses, -> { where(record_type: %w[A AAAA]) }
  # A / AAAA records whose IP belongs to no server of the fleet.
  scope :outside_fleet, -> { addresses.unattached.where(disabled: false) }

  # Manual links are per name: every record of "web.example.com" follows.
  def link_key = name

  def address? = record_type.in?(%w[A AAAA])

  def matched_label = matched_by.presence && I18n.t("technitium_record.matches.#{matched_by}", address: matched_address, default: "")
end
