# Coolify (read-only API tokens): the servers of each team and what runs on
# them (applications, services, databases), attached to the servers of the
# fleet. A token sees ONE team only (the API filters everything by the
# token's team and cannot list the others): one connection per team, and as
# many instances as needed.
class Integrations::Coolify < Integrations::Base
  self.key = "coolify"
  self.label = "Coolify"
  self.icon = :cube
  self.default_interval = 15

  # A resource stopped for longer is taken as stopped on purpose (no alert).
  STOPPED_FOR_DAYS = 30

  class << self
    # Shared by every connection: the alerts.
    def fields
      section = I18n.t("integrations.sections.alerts")
      [
        Integrations::Field.new(key: :alert_backups, label: I18n.t("integrations.coolify.alert_backups"), type: :boolean, default: true, section: section,
                                hint: I18n.t("integrations.coolify.alert_backups_hint")),
        Integrations::Field.new(key: :backup_max_age_hours, label: I18n.t("integrations.coolify.backup_max_age_hours"), type: :number, default: 26, section: section),
        Integrations::Field.new(key: :alert_no_backup, label: I18n.t("integrations.coolify.alert_no_backup"), type: :boolean, default: true, section: section),
        Integrations::Field.new(key: :alert_deploy_failed, label: I18n.t("integrations.coolify.alert_deploy_failed"), type: :boolean, default: true, section: section,
                                hint: I18n.t("integrations.coolify.alert_deploy_failed_hint")),
        Integrations::Field.new(key: :alert_resources, label: I18n.t("integrations.coolify.alert_resources"), type: :boolean, default: true, section: section,
                                hint: I18n.t("integrations.coolify.alert_resources_hint", count: STOPPED_FOR_DAYS)),
        Integrations::Field.new(key: :alert_server_unreachable, label: I18n.t("integrations.coolify.alert_server_unreachable"), type: :boolean, default: true, section: section),
        Integrations::Field.new(key: :alert_dns, label: I18n.t("integrations.coolify.alert_dns"), type: :boolean, default: true, section: section,
                                hint: I18n.t("integrations.coolify.alert_dns_hint")),
        Integrations::Field.new(key: :alert_no_health_check, label: I18n.t("integrations.coolify.alert_no_health_check"), type: :boolean, default: false, section: section,
                                hint: I18n.t("integrations.coolify.alert_no_health_check_hint"))
      ]
    end

    def connection_fields
      [
        Integrations::Field.new(key: :url, label: I18n.t("integrations.coolify.url"), type: :url, required: true, placeholder: "https://coolify.example.com"),
        Integrations::Field.new(key: :token, label: I18n.t("integrations.coolify.token"), secret: true, required: true, hint: I18n.t("integrations.coolify.token_hint"))
      ]
    end

    def client(connection) = Integrations::Coolify::Client.new(url: connection.value(:url), token: connection.value(:token))

    # The team and version the token reaches; warns when the token can read
    # secrets (read:sensitive or root: the private keys come unredacted).
    def test_connection(connection)
      client = client(connection)
      team = client.team
      message = I18n.t("integrations.coolify.valid_token", team: team["name"], version: client.version, count: client.servers.size)
      message += I18n.t("integrations.coolify.sensitive_token") if client.private_keys.any? { |key| key["private_key"].present? }
      message
    end

    def sync_connection(connection)
      result = Integrations::Coolify::Fetch.new(client(connection)).call
      Integrations::Coolify::Sync.new(connection, result).call
    end

    def connection_label(connection) = connection.state["team"]

    def connection_group(connection)
      URI.parse(connection.value(:url).to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def connection_summary(connection)
      state = connection.state
      return if state["servers"].nil?

      I18n.t("integrations.coolify.connection_summary", count: state["servers"], attached: state["attached"], resources: state["resources"], version: state["version"])
    end

    def help_partial = "integrations/coolify/help"

    # The backups of the databases Coolify runs on the server: the last one
    # failed (crit), none succeeded for too long (warn), none planned (warn).
    def health_reasons(integration, server)
      max_age = integration.value(:backup_max_age_hours).to_f.nonzero? || 26
      resources = server.coolify_resources.sort_by(&:name)
      deploys = resources.select { |resource| resource.kind == "application" && resource.deploy_failed? }
      deploys = integration.value(:alert_deploy_failed) ? deploys.map { |application| reason("warn", :deploy_failed, application: application.name) } : []
      servers = resources.select { |resource| resource.kind == "server" }
      unreachable = integration.value(:alert_server_unreachable) ? servers.reject { |coolify| coolify.data["reachable"] != false && coolify.data["usable"] != false } : []
      unreachable.map { |coolify| reason("crit", :server_unreachable, team: coolify.connection.label) } +
        resource_reasons(integration, resources) + dns_reasons(integration, server) + deploys + resources.select { |resource| resource.kind == "database" }.filter_map do |database|
        case database.backup_state(max_age)
        when :failed then reason("crit", :backup_failed, database: database.name) if integration.value(:alert_backups)
        when :late then reason("warn", :backup_late, database: database.name, count: max_age.round) if integration.value(:alert_backups)
        when :none then reason("warn", :no_backup, database: database.name) if integration.value(:alert_no_backup)
        end
      end
    end

    # Stopped (recently: it ran in the last STOPPED_FOR_DAYS days) or unhealthy
    # resources, and, if chosen, running applications without a health check.
    def resource_reasons(integration, resources)
      reasons = []
      if integration.value(:alert_resources)
        resources.each do |resource|
          next unless CoolifyResource::RESOURCE_KINDS.include?(resource.kind)

          if resource.stopped? && resource.online_since?(STOPPED_FOR_DAYS.days.ago)
            reasons << reason("warn", :stopped, kind: resource.kind_label.downcase, name: resource.name)
          elsif resource.unhealthy?
            reasons << reason("warn", :unhealthy, kind: resource.kind_label.downcase, name: resource.name)
          end
        end
      end
      if integration.value(:alert_no_health_check)
        resources.select { |resource| resource.kind == "application" && resource.running? && resource.data["health_check"] != true }
                 .each { |application| reasons << reason("warn", :no_health_check, name: application.name) }
      end
      reasons
    end

    # A domain served here whose DNS points elsewhere, or has no record in a
    # zone Elio reads (with a DNS extension: OVHcloud, Technitium, Gandi).
    def dns_reasons(integration, server)
      return [] unless integration.value(:alert_dns) && Dns.enabled?

      Integrations::Coolify::DomainCheck.new(server).problems.map do |domain|
        domain.state == :missing ? reason("warn", :dns_missing, domain: domain.name) : reason("warn", :dns_elsewhere, domain: domain.name, targets: domain.targets.first(3).join(", "))
      end
    end

    def reason(tone, key, **params) = Inventory::HealthStatus.reason(tone, "integrations.coolify.health.#{key}", **params)

    # A "Coolify" tab on the servers Coolify manages, with their resources; orange when one is stopped or unhealthy.
    def server_tabs
      [ { key: "coolify", label: "Coolify", visible: ->(server) { server.coolify_resources.any? },
          count: ->(server) { server.coolify_resources.resources.size.nonzero? },
          tone: ->(server) { :warn if server.coolify_resources.resources.any? { |resource| resource.stopped? || resource.unhealthy? } } } ]
    end

    def sidebar_links = [ { label: "Coolify", path: :coolify_path, icon: :cube, controller: "coolify", position: 4 } ]
  end
end
