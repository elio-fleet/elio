require "resolv"

class Server < ApplicationRecord
  # Activities logged when the health of the server or the state of its Docker changes.
  HEALTH_KINDS = { "ok" => :health_recovered, "warn" => :health_warning, "crit" => :health_critical }.freeze
  DOCKER_KINDS = { "ok" => :docker_recovered, "warn" => :docker_warning, "crit" => :docker_critical }.freeze

  has_many :account_snapshots, dependent: :delete_all
  has_many :temporary_accesses, dependent: :delete_all
  has_many :activities, dependent: :nullify
  has_many :server_group_memberships, dependent: :delete_all
  has_many :server_groups, -> { order(:name) }, through: :server_group_memberships
  has_many :inventory_snapshots, class_name: "Inventory::Snapshot", dependent: :delete_all
  has_many :health_samples, class_name: "Inventory::HealthSample", dependent: :delete_all
  has_many :packages, class_name: "Inventory::Package", dependent: :delete_all
  has_many :server_vulnerabilities, dependent: :delete_all
  has_many :notes, class_name: "ServerNote", dependent: :delete_all
  has_many :dns_records, dependent: :nullify
  # Tasks keep the server's name; a server deleted while waiting fails its items.
  has_many :background_task_items, dependent: :nullify
  has_many :uptime_kuma_monitors, -> { by_name }, dependent: :nullify
  has_many :ovh_resources, dependent: :nullify
  before_destroy(prepend: true) { BackgroundTaskItem.cancel_for_server!(self) }

  HEALTH_STATES = %w[ok warn crit unknown].freeze

  # How root commands run on the server (see Ssh::Connection#privilege), as
  # found by the last inventory: root, sudo or none.
  PRIVILEGES = %w[root sudo none].freeze
  validates :privilege, inclusion: { in: PRIVILEGES }, allow_nil: true

  scope :in_group, ->(group) { where(id: ServerGroupMembership.where(server_group: group).select(:server_id)) }
  HOSTNAME_REGEXP = /\A(?=.{1,253}\z)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\z/i

  normalizes :name, :host, :username, with: ->(value) { value.strip }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :host, presence: true
  validates :port, numericality: { only_integer: true, in: 1..65_535 }
  # A POSIX account name (useradd's default rule), never passed to a shell anyway.
  USERNAME_FORMAT = /\A[a-z_][a-z0-9_.-]{0,31}\z/i
  validates :username, presence: true, format: { with: USERNAME_FORMAT, allow_blank: true }
  validate :host_must_be_an_ip_or_hostname
  validate :extra_addresses_must_be_ips

  # Matching with external resources (probes, provider IPs): every address
  # by which the server is known.
  scope :with_address, ->(address) { where("servers.ip_addresses @> ?::jsonb OR servers.extra_addresses @> ?::jsonb OR servers.host = ?", [ address ].to_json, [ address ].to_json, address) }

  before_update :reset_reachability, if: -> { will_save_change_to_host? || will_save_change_to_port? }

  # Remembers whether the app could log in over SSH (see Ssh::Check); `nil` = unknown.
  # Logs ssh_access_lost when a server that accepted the Elio key refuses it.
  def record_ssh_status!(ok)
    lost = ssh_ok == true && ok == false
    changed = ssh_ok != ok
    update_columns(ssh_ok: ok, ssh_checked_at: Time.current)
    Activity.record!(:ssh_access_lost, server: self) if lost
    refresh_health! if changed && health_status.present?
  end

  # Remembers a ping result (see Servers::Ping) and logs when the server goes
  # down (server_unreachable) or comes back (server_back_online).
  def record_reachability!(reachable)
    previous = self.reachable
    update_columns(reachable: reachable, last_checked_at: Time.current)
    if !reachable && previous != false
      Activity.record!(:server_unreachable, server: self)
    elsif reachable && previous == false
      Activity.record!(:server_back_online, server: self)
    end
  end

  def inventory(category) = inventory_snapshots.find { |snapshot| snapshot.category == category.to_s }

  # Host name of the machine (os inventory), nil until collected.
  def hostname = inventory(:os)&.data&.dig("hostname")

  # Shown next to the name when it says something more (not the same name).
  def distinct_hostname
    hostname if hostname.present? && hostname.split(".").first.casecmp?(name.parameterize) == false && !hostname.casecmp?(name)
  end

  # The addresses allowed to reach its SSH port (SshSource): those chosen by
  # its groups (a group without a choice does not restrict), the whole list
  # when no group chose. Empty list = SSH open to everyone.
  def ssh_sources
    chosen = server_groups.flat_map(&:ssh_source_ids).uniq
    chosen.any? ? SshSource.where(id: chosen).ordered.to_a : SshSource.ordered.to_a
  end

  # The groups whose choice restricts its SSH sources (for the explanation).
  def ssh_source_groups = server_groups.select { |group| group.ssh_source_ids.any? }

  # Every address of the server: collected by the network inventory, added by
  # hand, and the SSH host when it is an IP. Public addresses first.
  def addresses
    ([ host ].select { |value| Inventory::IpScope.ip?(value) } + ip_addresses + extra_addresses).uniq
  end

  # Search of the fleet page: name, SSH host, host name or any address (part of it).
  def matches_search?(query)
    words = query.to_s.downcase.split
    haystack = [ name, host, hostname, *addresses, *dns_names ].compact.join(" ").downcase
    words.all? { |word| haystack.include?(word) }
  end

  # The DNS names that point to the server (every DNS source).
  def dns_names = dns_records.map(&:name).uniq

  # Text field of the form: "203.0.113.4, 2001:db8::1".
  def extra_addresses_text = extra_addresses.join(", ")

  def extra_addresses_text=(text)
    self.extra_addresses = text.to_s.split(/[\s,;]+/).map(&:strip).compact_blank.uniq
  end

  # Health shown in the interface: "off" when the last ping failed, otherwise
  # the state computed from the inventory (ok, warn, crit, unknown).
  def health_state = reachable == false ? "off" : (health_status || "unknown")

  # Main reasons of the health state, most serious first.
  def health_reason_texts = Array(health_reasons).map { |reason| Inventory::HealthStatus.text(reason) }

  # Reasons of the Docker state (docker_status, Inventory::DockerStatus: ok,
  # warn, crit, or nil without a readable Docker), most serious first.
  def docker_reason_texts = Array(docker_reasons).map { |reason| Inventory::HealthStatus.text(reason) }

  # Recomputes the health of the server (Inventory::HealthStatus) and the state
  # of its Docker (Inventory::DockerStatus), and logs each change between ok,
  # warn and crit (not on the first evaluation).
  def refresh_health!
    previous = { health: health_status, docker: docker_status }
    inventory_snapshots.reset
    health = Inventory::HealthStatus.evaluate(self)
    docker = Inventory::DockerStatus.evaluate(self)
    update_columns(health_status: health.state, health_reasons: health.reasons.map(&:to_h),
                   docker_status: docker.state, docker_reasons: docker.reasons.map(&:to_h))
    record_state_change(previous[:health], health, HEALTH_KINDS)
    record_state_change(previous[:docker], docker, DOCKER_KINDS)
  end

  private

  def record_state_change(previous, result, kinds)
    return if previous.nil? || previous == "unknown" || result.state.nil? || result.state == "unknown" || previous == result.state

    Activity.record!(kinds.fetch(result.state), server: self, user: nil, reasons: result.reasons.map(&:to_h).first(3))
  end

  # The last ping and SSH results no longer apply once the address changes.
  def reset_reachability
    self.reachable = nil
    self.last_checked_at = nil
    self.ssh_ok = nil
    self.ssh_checked_at = nil
  end

  def extra_addresses_must_be_ips
    invalid = extra_addresses.reject { |address| Inventory::IpScope.ip?(address) }
    errors.add(:extra_addresses_text, :invalid_ips, addresses: invalid.join(", ")) if invalid.any?
  end

  def host_must_be_an_ip_or_hostname
    return if host.blank?
    return if host.match?(Resolv::IPv4::Regex) || host.match?(Resolv::IPv6::Regex) || host.match?(HOSTNAME_REGEXP)

    errors.add(:host, :invalid)
  end
end
