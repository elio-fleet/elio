# Attaches every DNS record of the fleet, whatever its source, to its server:
# a manual link by name first (DnsLink), then the IP of an A / AAAA record
# (ServerDirectory: collected, added by hand or SSH addresses), then a CNAME
# to a name already attached (of any source) or to a server's host name.
# Only the rows that change are written. Returns the servers whose records
# changed (their health is to refresh).
class Dns::Matcher
  Match = Data.define(:server_id, :matched_by, :address)

  # CNAME to CNAME to A: a few passes are enough.
  CNAME_PASSES = 3

  def self.call(servers = Server.includes(:inventory_snapshots).to_a) = new(servers).call

  def initialize(servers)
    @directory = ServerDirectory.new(servers)
    @links = DnsLink.pluck(:name, :server_id).to_h
  end

  def call
    records = DnsRecord.all.to_a
    matches = records.to_h { |record| [ record.id, first_match(record) ] }
    CNAME_PASSES.times do
      names = records.each_with_object({}) { |record, attached| attached[record.name] ||= matches[record.id] if matches[record.id] }
      found = records.select { |record| record.record_type == "CNAME" && matches[record.id].nil? && !@links.key?(record.name) }.filter_map do |record|
        match = names[record.value]&.then { |target| Match.new(target.server_id, "cname", nil) } ||
                @directory.by_host(record.value, names: true)&.then { |server| Match.new(server.id, "cname", nil) }
        [ record.id, match ] if match
      end
      break if found.empty?

      matches.merge!(found.to_h)
    end
    write(records, matches)
  end

  private

  def first_match(record)
    if @links.key?(record.name)
      server_id = @links[record.name]
      return server_id && Match.new(server_id, "manual", nil)
    end
    return unless record.address?

    found = @directory.by_address(record.value)
    Match.new(found.server.id, "address", found.address) if found
  end

  def write(records, matches)
    changed = Set.new
    records.each do |record|
      match = matches[record.id]
      attributes = { server_id: match&.server_id, matched_by: match&.matched_by, matched_address: match&.address }
      next if attributes.all? { |key, value| record.public_send(key) == value }

      changed.merge([ record.server_id, match&.server_id ].compact)
      record.update_columns(**attributes, updated_at: Time.current)
    end
    Server.where(id: changed.to_a).to_a
  end
end
