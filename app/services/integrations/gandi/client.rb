require "json"

# Read-only client of the Gandi API v5 (https://api.gandi.net/docs/): GET only,
# the personal access token in an Authorization: Bearer header. The lists are
# paginated (page, per_page): every page is read. `organization` is the
# sharing_id: without it, Gandi lists only the domains of the personal
# organization of the token's owner.
class Integrations::Gandi::Client
  BASE = "https://api.gandi.net/v5".freeze
  PER_PAGE = 100
  MAX_PAGES = 50

  def initialize(token:, organization: nil, base: BASE)
    @token = token
    @organization = organization.presence
    @base = base
  end

  # [{ "fqdn", "domain_records_href", … }] of the domains served by LiveDNS.
  def livedns_domains = paginate("/livedns/domains", sharing: true)

  # [{ "rrset_name", "rrset_type", "rrset_ttl", "rrset_values" }] of a domain.
  def records(fqdn) = paginate("/livedns/domains/#{segment(fqdn)}/records")

  # [{ "fqdn", "dates" => { "registry_ends_at" }, "autorenew", "nameserver" => { "current" } }]
  def domains = paginate("/domain/domains", sharing: true)

  private

  def paginate(path, sharing: false)
    (1..MAX_PAGES).each_with_object([]) do |page, items|
      params = { page: page, per_page: PER_PAGE }
      params[:sharing_id] = @organization if sharing && @organization
      batch = get(path, params)
      raise Integrations::Error, I18n.t("integrations.gandi.unexpected") unless batch.is_a?(Array)

      items.concat(batch)
      break items if batch.size < PER_PAGE
    end
  end

  def get(path, params)
    body = Integrations::Http.get("#{@base}#{path}?#{URI.encode_www_form(params)}", service: "Gandi",
                                  headers: { "Authorization" => "Bearer #{@token}", "Accept" => "application/json" })
    JSON.parse(body)
  rescue JSON::ParserError
    raise Integrations::Error, I18n.t("integrations.gandi.unexpected")
  end

  def segment(fqdn)
    name = fqdn.to_s.downcase
    raise Integrations::Error, I18n.t("integrations.gandi.unexpected") unless name.match?(/\A[a-z0-9.-]+\z/)

    name
  end
end
