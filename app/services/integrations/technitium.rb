# Technitium DNS Server (read-only API token): the A, AAAA and CNAME records of
# its zones, attached to the servers they point to, with alerts for records
# pointing outside the fleet and servers without a DNS name.
class Integrations::Technitium < Integrations::Base
  self.key = "technitium"
  self.label = "Technitium DNS"
  self.icon = :globe
  self.default_interval = 60

  class << self
    def fields
      alerts = I18n.t("integrations.technitium.section_alerts")
      [
        Integrations::Field.new(key: :url, label: I18n.t("integrations.technitium.url"), type: :url, required: true, placeholder: "https://dns.example.com:53443",
                                hint: I18n.t("integrations.technitium.url_hint")),
        Integrations::Field.new(key: :api_token, label: I18n.t("integrations.technitium.api_token"), secret: true, required: true, hint: I18n.t("integrations.technitium.api_token_hint")),
        Integrations::Field.new(key: :allow_self_signed, label: I18n.t("integrations.technitium.self_signed"), type: :boolean, default: false),
        Integrations::Field.new(key: :zones, label: I18n.t("integrations.technitium.zones"), type: :list, default: [], placeholder: "example.com, lan.example.com",
                                hint: I18n.t("integrations.technitium.zones_hint")),
        Integrations::Field.new(key: :alert_outside, label: I18n.t("integrations.technitium.alert_outside"), type: :boolean, default: false, section: alerts),
        Integrations::Field.new(key: :alert_server_without_dns, label: I18n.t("integrations.technitium.alert_server_without_dns"), type: :boolean, default: false, section: alerts,
                                hint: I18n.t("integrations.technitium.alert_server_without_dns_hint"))
      ]
    end

    def client(integration)
      Integrations::Technitium::Client.new(url: integration.value(:url), token: integration.value(:api_token), verify_ssl: !integration.value(:allow_self_signed))
    end

    # The version, the zones the token can see, and a warning when it could
    # change them (it should only view).
    def test_connection(integration)
      client = client(integration)
      info = client.session.dig("info") || {}
      zones = client.zones
      permissions = info.dig("permissions", "Zones") || {}
      message = I18n.t("integrations.technitium.connected", version: info["version"] || "?", count: zones.size)
      message += I18n.t("integrations.technitium.writable") if permissions["canModify"] || permissions["canDelete"]
      message += I18n.t("integrations.technitium.http_warning") if integration.value(:url).to_s.start_with?("http://")
      message
    end

    def sync(integration) = Integrations::Technitium::Sync.new(integration, client(integration)).call

    def server_tabs = [ { key: "dns", label: I18n.t("integrations.technitium.tab"), count: ->(server) { server.technitium_records.size.nonzero? } } ]

    def sidebar_links = [ { label: I18n.t("integrations.technitium.tab"), path: :technitium_records_path, icon: :globe, controller: "technitium_records" } ]

    def help_partial = "integrations/technitium/help"

    def health_reasons(integration, server)
      return [] unless integration.last_synced_at && integration.value(:alert_server_without_dns)
      return [] if server.technitium_records.exists?

      [ Inventory::HealthStatus.reason("warn", "integrations.technitium.health.no_dns") ]
    end
  end
end
