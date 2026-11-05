# Technitium DNS Server (read-only API token): the A, AAAA and CNAME records of
# its zones, in the DNS of the fleet (Dns: attached to the servers, common
# DNS alerts).
class Integrations::Technitium < Integrations::Base
  self.key = "technitium"
  self.label = "Technitium DNS"
  self.icon = :globe
  self.default_interval = 60

  class << self
    def fields
      [
        Integrations::Field.new(key: :url, label: I18n.t("integrations.technitium.url"), type: :url, required: true, placeholder: "https://dns.example.com:53443",
                                hint: I18n.t("integrations.technitium.url_hint")),
        Integrations::Field.new(key: :api_token, label: I18n.t("integrations.technitium.api_token"), secret: true, required: true, hint: I18n.t("integrations.technitium.api_token_hint")),
        Integrations::Field.new(key: :allow_self_signed, label: I18n.t("integrations.technitium.self_signed"), type: :boolean, default: false),
        Integrations::Field.new(key: :zones, label: I18n.t("integrations.technitium.zones"), type: :list, default: [], placeholder: "example.com, lan.example.com",
                                hint: I18n.t("integrations.technitium.zones_hint"))
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

    # Its records are in the DNS of the fleet (DNS page and tab, see Dns).
    def dns_source?(_integration) = true

    def help_partial = "integrations/technitium/help"
  end
end
