require "net/http"
require "base64"

# Reads the digest of an image tag from its registry (Docker Registry HTTP
# API v2): HEAD /v2/<repository>/manifests/<tag>, after the token dance when
# the registry asks for one (WWW-Authenticate: Bearer realm=…, anonymous or
# with the credentials of the settings), or Basic auth; and the tags of a
# repository (GET /v2/<repository>/tags/list, pages followed by their Link
# header, at most TAG_PAGES). HTTPS only, read-only.
class ImageRegistry::Client
  ACCEPT = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json
              application/vnd.docker.distribution.manifest.v2+json application/vnd.oci.image.manifest.v1+json].join(", ")
  TIMEOUT = 10
  TAG_PAGES = 10
  TAGS_PER_PAGE = 1000

  class RateLimited < ImageRegistry::Error; end

  # Trusted certificates (nil: the system's); tests trust a local server.
  cattr_accessor :cert_store

  # `credentials`: { "ghcr.io" => ["user", "token"] }.
  def initialize(credentials: {})
    @credentials = credentials
    @tokens = {}
  end

  def digest(reference)
    uri = URI("https://#{reference.host}/v2/#{reference.repository}/manifests/#{reference.tag}")
    response = head(uri, authorization(reference))
    if response.is_a?(Net::HTTPUnauthorized) && (challenge = response["www-authenticate"])
      response = head(uri, authenticate(reference, challenge))
    end

    case response
    when Net::HTTPSuccess then response["docker-content-digest"].presence || raise(ImageRegistry::Error, I18n.t("image_registry.client.no_digest"))
    when Net::HTTPNotFound then raise ImageRegistry::Error, I18n.t("image_registry.client.tag_not_found")
    when Net::HTTPUnauthorized, Net::HTTPForbidden then raise ImageRegistry::Error, I18n.t("image_registry.client.access_refused")
    when Net::HTTPTooManyRequests then raise RateLimited, I18n.t("image_registry.client.rate_limited")
    else raise ImageRegistry::Error, I18n.t("image_registry.client.unexpected", code: response.code)
    end
  end

  # Every tag of the repository of `reference` (the first TAG_PAGES pages).
  def tags(reference)
    uri = URI("https://#{reference.host}/v2/#{reference.repository}/tags/list?n=#{TAGS_PER_PAGE}")
    tags = []
    TAG_PAGES.times do
      response = get(uri, authorization(reference))
      if response.is_a?(Net::HTTPUnauthorized) && (challenge = response["www-authenticate"])
        response = get(uri, authenticate(reference, challenge))
      end
      check!(response)
      tags.concat(Array(JSON.parse(response.body)["tags"]))
      link = response["link"].to_s[/<([^>]+)>;\s*rel="?next"?/, 1]
      break unless link

      uri = URI.join(uri, link)
      raise ImageRegistry::Error, I18n.t("image_registry.client.auth_https_only") unless uri.is_a?(URI::HTTPS) && uri.host == URI("https://#{reference.host}").host
    end
    tags
  rescue JSON::ParserError
    raise ImageRegistry::Error, I18n.t("image_registry.client.unexpected", code: "JSON")
  end

  private

  def check!(response)
    case response
    when Net::HTTPSuccess then response
    when Net::HTTPNotFound then raise ImageRegistry::Error, I18n.t("image_registry.client.tag_not_found")
    when Net::HTTPUnauthorized, Net::HTTPForbidden then raise ImageRegistry::Error, I18n.t("image_registry.client.access_refused")
    when Net::HTTPTooManyRequests then raise RateLimited, I18n.t("image_registry.client.rate_limited")
    else raise ImageRegistry::Error, I18n.t("image_registry.client.unexpected", code: response.code)
    end
  end

  def get(uri, authorization)
    request = Net::HTTP::Get.new(uri, "Accept" => "application/json", "User-Agent" => "Elio")
    request["Authorization"] = authorization if authorization
    http(uri) { |connection| connection.request(request) }
  end

  def authorization(reference) = @tokens[[ reference.registry, reference.repository ]]

  # Bearer: a pull token for the repository; Basic: the credentials as is.
  def authenticate(reference, challenge)
    user, password = @credentials[reference.registry]
    scheme, params = challenge.split(" ", 2)
    if scheme.casecmp?("basic")
      raise ImageRegistry::Error, I18n.t("image_registry.client.credentials_required") unless user

      return @tokens[[ reference.registry, reference.repository ]] = "Basic #{Base64.strict_encode64("#{user}:#{password}")}"
    end

    fields = params.to_s.scan(/(\w+)="([^"]*)"/).to_h
    realm = URI(fields.fetch("realm") { raise ImageRegistry::Error, "Authentification du registre illisible" })
    raise ImageRegistry::Error, I18n.t("image_registry.client.auth_https_only") unless realm.is_a?(URI::HTTPS)

    realm.query = URI.encode_www_form({ service: fields["service"], scope: fields["scope"] || "repository:#{reference.repository}:pull" }.compact)
    request = Net::HTTP::Get.new(realm, "User-Agent" => "Elio")
    request.basic_auth(user, password) if user
    response = http(realm) { |connection| connection.request(request) }
    raise ImageRegistry::Error, I18n.t("image_registry.client.token_refused", code: response.code) unless response.is_a?(Net::HTTPSuccess)

    token = JSON.parse(response.body).then { |body| body["token"] || body["access_token"] }
    raise ImageRegistry::Error, I18n.t("image_registry.client.unreadable_token") if token.blank?

    @tokens[[ reference.registry, reference.repository ]] = "Bearer #{token}"
  rescue JSON::ParserError
    raise ImageRegistry::Error, I18n.t("image_registry.client.unreadable_token")
  end

  def head(uri, authorization)
    request = Net::HTTP::Head.new(uri, "Accept" => ACCEPT, "User-Agent" => "Elio")
    request["Authorization"] = authorization if authorization
    http(uri) { |connection| connection.request(request) }
  end

  def http(uri, &block)
    options = { use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT }
    options[:cert_store] = cert_store if cert_store
    Net::HTTP.start(uri.host, uri.port, **options, &block)
  rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => e
    raise ImageRegistry::Error, I18n.t("image_registry.client.unreachable", truncate: (e.message.truncate(100)))
  end
end
