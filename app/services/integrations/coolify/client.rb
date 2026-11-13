require "json"

# Read-only client of the Coolify API (https://coolify.io/docs/api): GET only,
# the token in an Authorization: Bearer header, under <instance>/api/v1. A
# token sees one team only. Every uuid put in a path is checked first.
class Integrations::Coolify::Client
  UUID = /\A[a-z0-9]{1,64}\z/i

  def initialize(url:, token:)
    @base = "#{url.to_s.strip.chomp("/")}/api/v1"
    @token = token.to_s
  end

  def team = get("/team")
  def version = request("/version").strip.delete_prefix("v")
  def servers = list("/servers")
  def resources = list("/resources")
  def projects = list("/projects")
  def project(uuid) = get("/projects/#{segment(uuid)}")
  def server_domains(uuid) = list("/servers/#{segment(uuid)}/domains")
  def private_keys = list("/security/keys")

  def get(path, params = {})
    JSON.parse(request(path, params))
  rescue JSON::ParserError
    raise Integrations::Error, I18n.t("integrations.coolify.unexpected")
  end

  private

  def list(path, params = {})
    result = get(path, params)
    raise Integrations::Error, I18n.t("integrations.coolify.unexpected") unless result.is_a?(Array)

    result
  end

  def request(path, params = {})
    query = params.any? ? "?#{URI.encode_www_form(params)}" : ""
    Integrations::Http.get("#{@base}#{path}#{query}", service: "Coolify", headers: { "Authorization" => "Bearer #{@token}", "Accept" => "application/json" })
  end

  def segment(uuid)
    raise Integrations::Error, I18n.t("integrations.coolify.unexpected") unless uuid.to_s.match?(UUID)

    uuid.to_s
  end
end
