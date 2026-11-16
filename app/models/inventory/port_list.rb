# A list of ports written by hand, e.g. "22, 80, 443/tcp, 51820/udp,
# 6000-6007/tcp": each item is a port or a range, with an optional protocol.
# An item without one takes default_proto (nil: both TCP and UDP).
class Inventory::PortList
  ITEM = %r{\A(\d{1,5})(?:[-:](\d{1,5}))?(?:/(tcp|udp))?\z}
  PROTOCOLS = %w[tcp udp].freeze

  Item = Data.define(:from, :to, :proto) do
    def include?(port, proto) = port.between?(from, to) && (self.proto.nil? || self.proto == proto)

    def to_s = [ from == to ? from.to_s : "#{from}-#{to}", proto ].compact.join("/")
  end

  attr_reader :items, :invalid

  def initialize(text, default_proto: nil)
    @items = []
    @invalid = []
    text.to_s.split(/[\s,;]+/).compact_blank.each do |token|
      match = token.downcase.match(ITEM)
      from, to = match && [ match[1].to_i, (match[2] || match[1]).to_i ]
      if match && from.between?(1, 65_535) && to.between?(from, 65_535)
        @items << Item.new(from: from, to: to, proto: match[3] || default_proto.presence)
      else
        @invalid << token
      end
    end
  end

  def include?(port, proto) = items.any? { |item| item.include?(port.to_i, proto.to_s) }

  def empty? = items.empty?

  # "22/tcp, 6000-6007/tcp, 51820/udp": the items as they are checked.
  def to_s = items.join(", ")
end
