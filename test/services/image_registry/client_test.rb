require "test_helper"

class ImageRegistry::ClientTest < ActiveSupport::TestCase
  include HttpsServerHelpers
  include TcpHelpers

  DIGEST = "sha256:#{"9" * 64}"

  def reference(host, repository = "library/nginx", tag = "1.27") = ImageRegistry::Reference.new(registry: host, repository: repository, tag: tag)

  test "parses image references like Docker" do
    {
      "nginx:1.27" => [ "docker.io", "library/nginx", "1.27", "registry-1.docker.io" ],
      "nginx" => [ "docker.io", "library/nginx", "latest", "registry-1.docker.io" ],
      "acme/app:2" => [ "docker.io", "acme/app", "2", "registry-1.docker.io" ],
      "docker.io/library/redis:7" => [ "docker.io", "library/redis", "7", "registry-1.docker.io" ],
      "ghcr.io/acme/shop-worker:2.4.1" => [ "ghcr.io", "acme/shop-worker", "2.4.1", "ghcr.io" ],
      "localhost:5000/team/app" => [ "localhost:5000", "team/app", "latest", "localhost:5000" ]
    }.each do |text, expected|
      parsed = ImageRegistry::Reference.parse(text)
      assert_equal expected, [ parsed.registry, parsed.repository, parsed.tag, parsed.host ], text
    end
    assert_nil ImageRegistry::Reference.parse("nginx@sha256:#{"1" * 64}")
    assert_nil ImageRegistry::Reference.parse("sha256:#{"1" * 64}")
  end

  test "reads the digest of a tag after the anonymous token dance (Docker Hub, GHCR)" do
    handler = lambda do |method, path, headers|
      if path.start_with?("/token")
        http_response("200 OK", { token: "pull-token" }.to_json)
      elsif headers["authorization"] == "Bearer pull-token"
        http_response("200 OK", "", "Docker-Content-Digest" => DIGEST)
      else
        http_response("401 Unauthorized", "", "Www-Authenticate" => %(Bearer realm="https://#{headers["host"]}/token",service="registry.test",scope="repository:library/nginx:pull"))
      end.tap { assert_equal "HEAD", method unless path.start_with?("/token") }
    end
    with_https_server(ImageRegistry::Client, handler: handler) do |host, requests|
      client = ImageRegistry::Client.new
      assert_equal DIGEST, client.digest(reference(host))
      assert_equal DIGEST, client.digest(reference(host)), "the token is reused"
      paths = Array.new(requests.size) { requests.pop[1] }
      assert_equal [ "/v2/library/nginx/manifests/1.27", "/token?service=registry.test&scope=repository%3Alibrary%2Fnginx%3Apull",
                     "/v2/library/nginx/manifests/1.27", "/v2/library/nginx/manifests/1.27" ], paths
    end
  end

  test "sends the credentials of the registry to its token service, or as Basic auth" do
    seen = []
    handler = lambda do |_method, path, headers|
      seen << headers["authorization"]
      if path.start_with?("/token") then http_response("200 OK", { access_token: "private" }.to_json)
      elsif path.include?("basic") && headers["authorization"]&.start_with?("Basic") then http_response("200 OK", "", "Docker-Content-Digest" => DIGEST)
      elsif path.include?("basic") then http_response("401 Unauthorized", "", "Www-Authenticate" => %(Basic realm="registry"))
      elsif headers["authorization"] == "Bearer private" then http_response("200 OK", "", "Docker-Content-Digest" => DIGEST)
      else http_response("401 Unauthorized", "", "Www-Authenticate" => %(Bearer realm="https://#{headers["host"]}/token"))
      end
    end
    with_https_server(ImageRegistry::Client, handler: handler) do |host|
      client = ImageRegistry::Client.new(credentials: { host => %w[elio s3cret] })
      assert_equal DIGEST, client.digest(reference(host, "acme/private"))
      assert_equal DIGEST, client.digest(reference(host, "acme/basic"))
      assert_includes seen, "Basic #{Base64.strict_encode64("elio:s3cret")}"

      error = assert_raises(ImageRegistry::Error) { ImageRegistry::Client.new.digest(reference(host, "acme/basic")) }
      assert_match "demande des identifiants", error.message
    end
  end

  test "errors are readable; a rate limit is told apart" do
    handler = lambda do |_method, path, _headers|
      if path.include?("missing") then http_response("404 Not Found")
      elsif path.include?("limited") then http_response("429 Too Many Requests")
      else http_response("200 OK")
      end
    end
    with_https_server(ImageRegistry::Client, handler: handler) do |host|
      client = ImageRegistry::Client.new
      assert_match "Tag introuvable", assert_raises(ImageRegistry::Error) { client.digest(reference(host, "acme/missing")) }.message
      assert_raises(ImageRegistry::Client::RateLimited) { client.digest(reference(host, "acme/limited")) }
      assert_match "pas d'empreinte", assert_raises(ImageRegistry::Error) { client.digest(reference(host, "acme/nodigest")) }.message
    end
    assert_match "injoignable", assert_raises(ImageRegistry::Error) { ImageRegistry::Client.new.digest(reference("127.0.0.1:#{closed_port}")) }.message
  end

test "reads the tags of a repository, page after page, after the token dance" do
  handler = lambda do |_method, path, headers|
    if path.start_with?("/token") then http_response("200 OK", { token: "pull-token" }.to_json)
    elsif headers["authorization"] != "Bearer pull-token"
      http_response("401 Unauthorized", "", "Www-Authenticate" => %(Bearer realm="https://#{headers["host"]}/token",service="registry.test"))
    elsif path.include?("last=7.0.11") then http_response("200 OK", { name: "library/redis", tags: %w[7.0.15 7.4.6] }.to_json)
    else http_response("200 OK", { name: "library/redis", tags: %w[7.0.10 7.0.11] }.to_json, "Link" => %(</v2/library/redis/tags/list?n=1000&last=7.0.11>; rel="next"))
    end
  end
  with_https_server(ImageRegistry::Client, handler: handler) do |host|
    assert_equal %w[7.0.10 7.0.11 7.0.15 7.4.6], ImageRegistry::Client.new.tags(reference(host, "library/redis", "7.0.11"))
  end
end

test "an authentication address in plain HTTP is refused" do
    handler = ->(_method, _path, _headers) { http_response("401 Unauthorized", "", "Www-Authenticate" => %(Bearer realm="http://evil.test/token")) }
    with_https_server(ImageRegistry::Client, handler: handler) do |host|
      assert_match "HTTPS seulement", assert_raises(ImageRegistry::Error) { ImageRegistry::Client.new(credentials: { host => %w[a b] }).digest(reference(host)) }.message
    end
  end
end
