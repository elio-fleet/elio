# An address or a network allowed to reach the SSH port of the servers
# ("Elio → 203.0.113.5", "Office → 198.51.100.0/24"). The suggested ufw rules
# and the firewall prompt restrict SSH to the sources of the server
# (Server#ssh_sources). Elio never applies them.
class SshSource < ApplicationRecord
  normalizes :name, with: ->(value) { value.squish }
  normalizes :cidr, with: ->(value) { normalize_cidr(value) }

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { case_sensitive: false }
  validate :cidr_must_be_an_address

  scope :ordered, -> { order(:position, :id) }

  # "203.0.113.5", "198.51.100.0/24", "2001:db8::/32": the network address,
  # without the prefix of a single address. Unparsable values are kept as they are.
  def self.normalize_cidr(value)
    text = value.to_s.strip
    address = IPAddr.new(text)
    prefix = address.prefix
    full = address.ipv4? ? 32 : 128
    prefix == full ? address.to_s : "#{address}/#{prefix}"
  rescue IPAddr::Error, ArgumentError
    text
  end

  def ipv6? = IPAddr.new(cidr).ipv6?

  # Safe for a ufw comment ("ssh (Elio)").
  def comment_name = name.gsub(/[^\w .@-]/, "").first(30)

  def label = "#{name} (#{cidr})"

  # Moves the source one step up (-1) or down (+1) in the list.
  def move!(step)
    sources = self.class.ordered.to_a
    index = sources.index(self)
    target = index + step
    return if target.negative? || target >= sources.size

    sources[index], sources[target] = sources[target], sources[index]
    transaction { sources.each_with_index { |source, position| source.update_columns(position: position) } }
  end

  private

  def cidr_must_be_an_address
    IPAddr.new(cidr.to_s)
  rescue IPAddr::Error, ArgumentError
    errors.add(:cidr, :invalid)
  end
end
