require "json"

# Read-only client of the Technitium DNS Server HTTP API (APIDOCS.md of
# TechnitiumSoftware/DnsServer): GET only, the API token in an
# Authorization: Bearer header (never in the URL, so not in its logs).
class Integrations::Technitium::Client
  def initialize(url:, token:, verify_ssl: true)
    @url = url.to_s.chomp("/")
    @token = token
    @verify_ssl = verify_ssl
  end

  # The token's session: Technitium version and permissions.
  def session = get("/api/user/session/get")

  def zones = Array(get("/api/zones/list").dig("response", "zones"))

  def records(zone) = Array(get("/api/zones/records/get", domain: zone, zone: zone, listZone: true).dig("response", "records"))

  def get(path, **params)
    query = params.any? ? "?#{URI.encode_www_form(params)}" : ""
    body = Integrations::Http.get("#{@url}#{path}#{query}", service: "Technitium", headers: { "Authorization" => "Bearer #{@token}", "Accept" => "application/json" },
                                                            verify_ssl: @verify_ssl)
    data = JSON.parse(body)
    case data["status"]
    when "ok" then data
    when "invalid-token" then raise Integrations::Error, I18n.t("integrations.technitium.invalid_token")
    else raise Integrations::Error, I18n.t("integrations.technitium.api_error", message: data["errorMessage"].presence || data["status"].to_s)
    end
  rescue JSON::ParserError
    raise Integrations::Error, I18n.t("integrations.technitium.not_json")
  end
end
