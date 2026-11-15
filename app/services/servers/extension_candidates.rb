require "csv"

# Servers the enabled extensions know but the fleet does not: OVHcloud
# services (dedicated servers, VPS, Public Cloud instances) and Coolify
# servers that no Elio server is attached to. The import page turns them into
# CSV, so they go through the same preview (and can be edited) as a file.
class Servers::ExtensionCandidates
  Candidate = Data.define(:source, :name, :host, :port, :username)

  # Coolify names the server it runs on by an address Elio cannot reach.
  LOCAL_HOSTS = %w[localhost host.docker.internal].freeze

  def self.call = (ovh + coolify).uniq { |candidate| candidate.host.downcase }

  def self.csv(candidates)
    CSV.generate do |csv|
      csv << %w[name host port user]
      candidates.each { |candidate| csv << [ candidate.name, candidate.host, candidate.port, candidate.username ] }
    end
  end

  def self.ovh
    return [] unless Integration.enabled?("ovh")

    OvhResource.services.unattached.order(:kind, :name).filter_map do |resource|
      host = preferred_address([ resource.data["ip"], *resource.addresses ])
      Candidate.new("OVHcloud", resource.name, host, nil, nil) if host
    end
  end

  def self.coolify
    return [] unless Integration.enabled?("coolify")

    CoolifyResource.servers.where(server_id: nil).ordered.filter_map do |resource|
      host = resource.data["ip"].to_s.strip
      next if host.blank? || LOCAL_HOSTS.include?(host.downcase) || Inventory::IpScope.of(host) == "local"

      Candidate.new("Coolify", resource.name, host, resource.data["port"], resource.data["user"].presence)
    end
  end

  # A public IPv4 first (the one SSH usually listens on), then any IPv4, then anything.
  def self.preferred_address(addresses)
    addresses = addresses.compact.map { |address| address.to_s.strip.delete_suffix("/32") }.reject(&:blank?).uniq
    ipv4 = addresses.select { |address| Inventory::IpScope.ip?(address) && IPAddr.new(address).ipv4? }
    ipv4.find { |address| Inventory::IpScope.of(address) == "public" } || ipv4.first || addresses.first
  end

  private_class_method :ovh, :coolify, :preferred_address
end
