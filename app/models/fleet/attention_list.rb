# What needs attention on the fleet, most serious first, for the "À traiter"
# list of the overview: unreachable servers, health concerns (or a refused
# Elio key), unknown keys, pending security updates, servers never inventoried;
# then, apart (docker_items), Docker: the servers whose Docker is to watch or
# critical (Inventory::DockerStatus) and the fixable CVEs of the images.
# Each item names its action ("See the disks") and the servers it is about.
# Servers must come with their inventory snapshots loaded.
class AttentionList
  Item = Data.define(:tone, :icon, :subject, :text, :action, :path, :servers) do
    def initialize(tone:, icon:, subject:, text:, action:, path:, servers: [])
      super
    end
  end

  # The action of a health reason: its label (attention_list.actions.<key>) and the tab it opens.
  REASON_ACTIONS = {
    "disk" => [ :disks, nil, "disks" ], "inodes" => [ :disks, nil, "disks" ], "memory" => [ :health, nil, "server-health-details" ], "load" => [ :health, nil, "server-health-details" ],
    "vulnerability" => [ :fixes, "vulnerabilities" ], "vulnerabilities" => [ :fixes, "vulnerabilities" ],
    "service_failed" => [ :services, "services" ], "services_failed" => [ :services, "services" ],
    "units_failed" => [ :services, "services" ], "units_failed_more" => [ :services, "services" ],
    "timer_failed" => [ :schedules, "schedules" ], "timers_failed" => [ :schedules, "schedules" ], "timer_late" => [ :schedules, "schedules" ], "timers_late" => [ :schedules, "schedules" ],
    "port_unexpected" => [ :ports, "ports" ], "ports_unexpected" => [ :ports, "ports" ]
  }.freeze

  TONE_ORDER = { "crit" => 0, "warn" => 1, "info" => 2 }.freeze

  def initialize(servers, insights:, summary:, routes: Rails.application.routes.url_helpers)
    @servers = servers.to_a
    @insights = insights
    @summary = summary
    @routes = routes
  end

  # The named action of a health (or Docker) reason of a server: [label, path], or a plain "See".
  def self.action_for(server, reason, routes = Rails.application.routes.url_helpers)
    key = reason["key"].to_s
    return [ I18n.t("attention_list.see_docker"), routes.server_path(server, tab: "docker") ] if key.start_with?("health.container", "health.image")

    label, tab, anchor = REASON_ACTIONS[key.delete_prefix("health.")] || EXTENSION_ACTIONS.find { |prefix, _| key.start_with?(prefix) }&.last
    return [ I18n.t("attention_list.see"), routes.server_path(server) ] unless label

    [ I18n.t("attention_list.actions.#{label}"), routes.server_path(server, tab: tab, anchor: anchor) ]
  end

  def items
    @items ||= (server_items + fleet_items).sort_by { |item| [ TONE_ORDER.fetch(item.tone), item.subject ] }
  end

  def docker_items
    @docker_items ||= (docker_server_items + [ image_vulnerabilities_item ].compact).sort_by { |item| [ TONE_ORDER.fetch(item.tone), item.subject ] }
  end

  def any? = items.any? || docker_items.any?

  def size = items.size + docker_items.size

  # Everything, Docker included, by gravity: { "crit" => [...], "warn" => [...], "info" => [...] }.
  def by_tone = (items + docker_items).sort_by { |item| [ TONE_ORDER.fetch(item.tone), item.subject ] }.group_by(&:tone)

  private

  def server_items
    @servers.flat_map do |server|
      items = []
      if server.health_state == "off"
        items << Item.new("crit", :signal_slash, server.name, I18n.t("attention_list.unreachable"), I18n.t("attention_list.actions.connection"), @routes.server_path(server), [ server_ref(server) ])
      elsif (reasons = Array(server.health_reasons)).any?
        first = reasons.first
        more = reasons.size > 1 ? " (+#{reasons.size - 1})" : ""
        label, path = reason_action(server, first)
        items << Item.new(first["tone"], first["tone"] == "crit" ? :x_mark : :exclamation_triangle, server.name, "#{Inventory::HealthStatus.text(first)}#{more}", label, path, [ server_ref(server) ])
      elsif server.ssh_ok == false
        items << Item.new("crit", :key, server.name, I18n.t("attention_list.key_refused"), I18n.t("attention_list.install_key"), @routes.server_path(server), [ server_ref(server) ])
      end
      if (orphans = @insights.orphans_by_server_id[server.id]).present?
        items << Item.new("warn", :key, server.name, I18n.t("attention_list.unknown_keys", count: orphans.size), I18n.t("attention_list.see_keys"), @routes.server_path(server, tab: "keys"), [ server_ref(server) ])
      end
      if server.inventoried_at.nil? && server.ssh_ok
        items << Item.new("info", :pulse, server.name, I18n.t("attention_list.no_inventory"), I18n.t("attention_list.actions.inventory"), @routes.server_path(server), [ server_ref(server) ])
      end
      items
    end
  end

  def fleet_items
    [ security_updates_item, vulnerabilities_item ].compact
  end

  def docker_server_items
    @servers.filter_map do |server|
      next unless server.docker_status.in?(%w[warn crit])

      reasons = Array(server.docker_reasons)
      more = reasons.size > 1 ? " (+#{reasons.size - 1})" : ""
      Item.new(server.docker_status, :docker, server.name, "#{Inventory::HealthStatus.text(reasons.first)}#{more}", I18n.t("attention_list.see_docker"),
               @routes.server_path(server, tab: "docker"), [ server_ref(server) ])
    end
  end

  def security_updates_item
    return unless @summary.security_updates.positive?

    servers = @servers.select { |server| server.inventory("health")&.data&.dig("updates", "security").to_i.positive? }
    Item.new("warn", :shield_check, I18n.t("count.servers", count: servers.size), I18n.t("attention_list.security_updates", count: @summary.security_updates),
             I18n.t("attention_list.see_packages"), @routes.packages_path, servers.map { |server| server_ref(server) })
  end

  # Fixable CVEs at the alert severity of the settings, on the whole fleet:
  # the servers' own packages (critical), their Docker images (a warning, in
  # the Docker group, when the Docker alerts ask for it).
  def vulnerabilities_item
    serious_vulnerabilities_item("crit", :host, :vulnerabilities, :shield_exclamation, I18n.t("attention_list.see_vulnerabilities")) do |minimum|
      @routes.vulnerabilities_path(fixable: 1, severity: minimum, origin: "host")
    end
  end

  def image_vulnerabilities_item
    return unless AppSetting.current.docker_alert_vulnerabilities

    serious_vulnerabilities_item("warn", :images, :image_vulnerabilities, :docker, I18n.t("attention_list.see_images")) do |minimum|
      @routes.vulnerabilities_path(fixable: 1, severity: minimum, origin: "image")
    end
  end

  def serious_vulnerabilities_item(tone, origin_scope, key, icon, action)
    minimum = AppSetting.current.vulnerability_alert_severity
    return if minimum == "none"

    scope = ServerVulnerability.public_send(origin_scope).fixable.at_least(minimum)
    cves = scope.distinct.count(:cve)
    return if cves.zero?

    ids = scope.distinct.pluck(:server_id)
    servers = @servers.select { |server| ids.include?(server.id) }
    Item.new(tone, icon, I18n.t("count.servers", count: servers.size), I18n.t("attention_list.#{key}", count: cves), action, yield(minimum), servers.map { |server| server_ref(server) })
  end

  def server_ref(server) = [ server.name, @routes.server_path(server) ]

  # Reasons raised by the extensions, by the start of their key.
  EXTENSION_ACTIONS = { "integrations.uptime_kuma." => [ :probes, "monitors" ], "dns." => [ :dns, "dns" ],
                        "integrations.ovh.health.expiring" => [ :hosting, "ovh" ], "integrations.ovh." => [ :ports, "firewall" ],
                        "integrations.coolify.health.dns" => [ :dns, "dns" ],
                        "integrations.coolify.health.stale_key" => [ :keys, "keys" ], "integrations.coolify." => [ :coolify, "coolify" ] }.freeze

  def reason_action(server, reason) = self.class.action_for(server, reason, @routes)
end
