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

  class << self
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
  end
end
