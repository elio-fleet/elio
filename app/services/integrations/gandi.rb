# Gandi (personal access token, read rights only): the A, AAAA and CNAME
# records of the domains served by LiveDNS, in the DNS of the fleet (Dns:
# attached to the servers, common DNS alerts), and the domains with their
# expiry date (optional alert, like OVHcloud). API v5, https://api.gandi.net/docs/.
class Integrations::Gandi < Integrations::Base
  self.key = "gandi"
  self.label = "Gandi"
  self.icon = :globe
  self.default_interval = 60

  class << self
    def fields
      alerts = I18n.t("integrations.sections.alerts")
      [
        Integrations::Field.new(key: :api_token, label: I18n.t("integrations.gandi.api_token"), secret: true, required: true, hint: I18n.t("integrations.gandi.api_token_hint")),
        Integrations::Field.new(key: :organization, label: I18n.t("integrations.gandi.organization"), placeholder: "0b1b5c4e-…", hint: I18n.t("integrations.gandi.organization_hint")),
        Integrations::Field.new(key: :domains, label: I18n.t("integrations.gandi.domains"), type: :list, default: [], placeholder: "example.com, example.fr",
                                hint: I18n.t("integrations.gandi.domains_hint")),
        Integrations::Field.new(key: :alert_expiring, label: I18n.t("integrations.gandi.alert_expiring"), type: :boolean, default: false, section: alerts),
        Integrations::Field.new(key: :expiring_days, label: I18n.t("integrations.gandi.expiring_days"), type: :number, default: 30, section: alerts),
        Integrations::Field.new(key: :expiring_ignore_auto_renew, label: I18n.t("integrations.gandi.expiring_ignore_auto_renew"), type: :boolean, default: true, section: alerts)
      ]
    end

    def client(integration)
      Integrations::Gandi::Client.new(token: integration.value(:api_token), organization: integration.value(:organization))
    end

    # The domains the token can see, and how many are served by LiveDNS.
    def test_connection(integration)
      client = client(integration)
      livedns = client.livedns_domains
      domains = client.domains
      I18n.t("integrations.gandi.connected", count: domains.size, livedns: livedns.size) + I18n.t("integrations.gandi.read_only_reminder")
    end

    def sync(integration) = Integrations::Gandi::Sync.new(integration, client(integration)).call

    # Its records are in the DNS of the fleet (DNS page and tab, see Dns).
    def dns_source?(_integration) = true

    def help_partial = "integrations/gandi/help"

    # The domains read at the last sync ({ "fqdn", "expires_at", "autorenew", "livedns" }).
    def domains(integration) = Array(integration.state["domains"])

    # The domains that expire within the chosen number of days.
    def expiring_domains(integration)
      limit = integration.value(:expiring_days).to_i.days.from_now
      domains(integration).select do |domain|
        expires = domain["expires_at"] && Time.zone.parse(domain["expires_at"])
        expires && expires <= limit && !(integration.value(:expiring_ignore_auto_renew) && domain["autorenew"])
      end
    end
  end
end
