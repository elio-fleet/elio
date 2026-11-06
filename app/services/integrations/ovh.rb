# OVHcloud (read-only API keys): IP blocks with their reverse, network
# firewall and anti-DDoS, DNS records, dedicated servers, VPS and Public
# Cloud instances, attached to the servers they belong to. Each product and
# each alert is chosen in the extension's settings.
class Integrations::Ovh < Integrations::Base
  self.key = "ovh"
  self.label = "OVHcloud"
  self.icon = :globe
  self.default_interval = 360

  class << self
    def fields
      [
        Integrations::Field.new(key: :endpoint, label: I18n.t("integrations.ovh.endpoint"), type: :select, default: "ovh-eu",
                  options: [ [ I18n.t("integrations.ovh.ovh_eu"), "ovh-eu" ], [ I18n.t("integrations.ovh.ovh_ca"), "ovh-ca" ], [ I18n.t("integrations.ovh.ovh_us"), "ovh-us" ] ]),
        Integrations::Field.new(key: :application_key, label: "Application Key", required: true),
        Integrations::Field.new(key: :application_secret, label: "Application Secret", secret: true, required: true),
        Integrations::Field.new(key: :consumer_key, label: "Consumer Key", secret: true, required: true,
                  hint: I18n.t("integrations.ovh.consumer_key_hint")),

        Integrations::Field.new(key: :products, label: I18n.t("integrations.ovh.products"), type: :checkboxes, section: I18n.t("integrations.sections.resources"),
                  options: Integrations::Ovh::Fetch::PRODUCTS.map { |product| [ product, I18n.t("integrations.ovh.product_labels.#{product}") ] }, default: Integrations::Ovh::Fetch::PRODUCTS),
        Integrations::Field.new(key: :zones, label: I18n.t("integrations.ovh.zones"), type: :list, default: [], section: I18n.t("integrations.sections.resources"), placeholder: "example.com, example.fr",
                  hint: I18n.t("integrations.ovh.zones_hint")),
        Integrations::Field.new(key: :projects, label: I18n.t("integrations.ovh.projects"), type: :list, default: [], section: I18n.t("integrations.sections.resources"), placeholder: I18n.t("integrations.ovh.projects_placeholder"),
                  hint: I18n.t("integrations.ovh.projects_hint")),

        Integrations::Field.new(key: :alert_expiring, label: I18n.t("integrations.ovh.alert_expiring"), type: :boolean, default: true, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :expiring_days, label: I18n.t("integrations.ovh.expiring_days"), type: :number, default: 30, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :expiring_ignore_auto_renew, label: I18n.t("integrations.ovh.expiring_ignore_auto_renew"), type: :boolean, default: true, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :alert_firewall_disabled, label: I18n.t("integrations.ovh.alert_firewall_disabled"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :alert_reverse_mismatch, label: I18n.t("integrations.ovh.alert_reverse_mismatch"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts")),
        Integrations::Field.new(key: :alert_unmanaged_service, label: I18n.t("integrations.ovh.alert_unmanaged_service"), type: :boolean, default: false, section: I18n.t("integrations.sections.alerts"),
                  hint: I18n.t("integrations.ovh.alert_unmanaged_service_hint"))
      ]
    end

    def client(integration)
      Integrations::Ovh::Client.new(endpoint: integration.value(:endpoint), application_key: integration.value(:application_key),
                                    application_secret: integration.value(:application_secret), consumer_key: integration.value(:consumer_key))
    end

    # Checks the key and its rights: every chosen product readable, and warns
    # when the key could change something (a right other than GET).
    def test_connection(integration)
      credential = client(integration).get("/auth/currentCredential")
      rules = Array(credential["rules"])
      writes = rules.reject { |rule| rule["method"] == "GET" }.map { |rule| "#{rule["method"]} #{rule["path"]}" }
      missing = Integrations::Ovh::Fetch.rights(products(integration)).reject do |path|
        rules.any? { |rule| rule["method"].in?(%w[GET ALL]) && File.fnmatch(rule["path"], path) }
      end
      message = I18n.t("integrations.ovh.valid_key", status: credential["status"] || I18n.t("integrations.ovh.validated"))
      message += ". Droits manquants : #{missing.map { |path| "GET #{path}" }.join(", ")}" if missing.any?
      message += I18n.t("integrations.ovh.writable", writes_first: (writes.first(4).join(", "))) if writes.any?
      message
    end

    def sync(integration)
      resources = Integrations::Ovh::Fetch.new(client(integration), products: products(integration), zones: integration.value(:zones),
                                               projects: integration.value(:projects)).call
      Integrations::Ovh::Sync.new(integration, resources).call
    end

    def products(integration) = Array(integration.value(:products))

    # With the DNS product, its records are in the DNS of the fleet.
    def dns_source?(integration) = products(integration).include?("dns")

    # Rights to give to the API key, and the prefilled token creation page.
    def rights(integration) = Integrations::Ovh::Fetch.rights(products(integration))

    def token_url(integration)
      base = Integrations::Ovh::Client::TOKEN_PAGES.fetch(integration.value(:endpoint).to_s, Integrations::Ovh::Client::TOKEN_PAGES["ovh-eu"])
      "#{base}?#{rights(integration).map { |path| "GET=#{path}" }.join("&")}" # (paths are made of / and * only, like in OVH docs)
    end

    def server_tabs = [ { key: "ovh", label: "OVH", count: ->(server) { server.ovh_resources.size.nonzero? } } ]

    def sidebar_links = [ { label: "OVHcloud", path: :ovh_path, icon: :globe, controller: "ovh" } ]

    def help_partial = "integrations/ovh/help"

    def expiring_services(integration)
      scope = OvhResource.services.where(expires_at: ..integration.value(:expiring_days).to_i.days.from_now.to_date)
      integration.value(:expiring_ignore_auto_renew) ? scope.where("NOT COALESCE((ovh_resources.data->>'renew_automatic')::boolean, false)") : scope
    end


    def health_reasons(integration, server)
      return [] unless integration.last_synced_at

      resources = server.ovh_resources.to_a
      return [] if resources.empty?

      reasons = []
      if integration.value(:alert_expiring)
        expiring = expiring_services(integration).where(server: server)
        expiring.each { |service| reasons << reason(service.days_left.to_i <= 7 ? "crit" : "warn", :expiring, name: service.name, count: service.days_left.to_i) }
      end
      ip_blocks = resources.select { |resource| resource.kind == "ip" }
      if integration.value(:alert_firewall_disabled)
        disabled = ip_blocks.flat_map { |block| Array(block.data["firewall"]).select { |_ip, firewall| firewall["enabled"] == false }.map(&:first) }
        missing = ip_blocks.select { |block| block.data.key?("firewall") && block.data["firewall"].empty? }.map(&:name)
        (disabled + missing).uniq.each { |ip| reasons << reason("warn", :firewall_disabled, ip: ip) }
      end
      if integration.value(:alert_reverse_mismatch) && server.hostname.present?
        ip_blocks.each do |block|
          Array(block.data["reverse"]).each do |ip, reverse|
            next if reverse.to_s.casecmp?(server.hostname)

            reasons << (reverse.blank? ? reason("warn", :no_reverse, ip: ip) : reason("warn", :reverse_mismatch, ip: ip, reverse: reverse))
          end
        end
      end
      reasons
    end

    private

    def reason(tone, key, **params) = Inventory::HealthStatus.reason(tone, "integrations.ovh.health.#{key}", **params)
  end
end
