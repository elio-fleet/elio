require "test_helper"

class Integrations::GandiTest < ActiveSupport::TestCase
  include StubHelpers
  include GandiHelpers

  setup do
    @integration = enable_gandi
    fake_gandi
    servers(:web).update!(extra_addresses_text: "203.0.113.10, 2001:db8::10")
    servers(:db).update!(extra_addresses_text: "10.0.0.12")
  end

  def sync = Integrations::Gandi.sync(@integration.reload)

  test "reads with GET and a Bearer token, never the token in the URL; the organization as sharing_id" do
    sync
    assert @gandi_requests.any?
    @gandi_requests.each do |url, options|
      assert url.start_with?("https://api.gandi.net/v5/")
      assert_not_includes url, "pat_test"
      assert_equal "Bearer pat_test-123", options.dig(:headers, "Authorization")
    end
    assert @gandi_requests.none? { |url, _| url.include?("sharing_id") }

    @integration.update!(settings: @integration.settings.merge("organization" => "org-42"))
    fake_gandi
    sync
    lists = @gandi_requests.map(&:first).reject { |url| url.include?("/records") }
    assert lists.all? { |url| URI.decode_www_form(URI(url).query).to_h["sharing_id"] == "org-42" }
    assert @gandi_requests.map(&:first).select { |url| url.include?("/records") }.none? { |url| url.include?("sharing_id") }
  end

  test "stores the A, AAAA and CNAME records: @ is the domain, relative CNAMEs, one line per value" do
    assert_equal "2 domaines LiveDNS, 8 enregistrements, 2 rattachés à aucun serveur", sync

    rows = DnsRecord.of_source("gandi").order(:name, :record_type, :value).map { |record| [ record.name, record.record_type, record.value, record.server&.name ] }
    assert_equal [
      [ "api.example.com", "A", "198.51.100.99", nil ],
      [ "api.example.com", "A", "203.0.113.10", "Web" ],
      [ "app.example.com", "CNAME", "api.example.com", "Web" ],
      [ "cdn.example.com", "CNAME", "cdn.provider.example", nil ],
      [ "example.com", "A", "203.0.113.10", "Web" ],
      [ "example.org", "A", "10.0.0.12", "Database" ],
      [ "v6.example.com", "AAAA", "2001:db8::10", "Web" ],
      [ "www.example.com", "CNAME", "example.com", "Web" ]
    ], rows
    assert_not DnsRecord.exists?(record_type: "MX")
    assert_equal "Gandi", DnsRecord.of_source("gandi").first.source_label
  end

  test "only the domains chosen; every page of a list is read" do
    @integration.update!(settings: @integration.settings.merge("domains" => [ "example.org" ]))
    sync
    assert_equal [ "example.org" ], DnsRecord.of_source("gandi").distinct.pluck(:zone)
    assert_equal [ "example.org" ], Integrations::Gandi.domains(@integration.reload).map { |domain| domain["fqdn"] }

    many = (1..150).map { |index| { "fqdn" => "d#{index}.example.com" } }
    pages = []
    fake_gandi({ "/v5/livedns/domains" => ->(params) { pages << params["page"]; many.each_slice(100).to_a.fetch(params["page"].to_i - 1, []).to_json } })
    assert_equal 150, Integrations::Gandi.client(@integration).livedns_domains.size
    assert_equal %w[1 2], pages
  end

  test "the domains with their expiry; the expiring ones logged once, not on the first sync, when the alert is on" do
    sync
    domains = Integrations::Gandi.domains(@integration.reload).index_by { |domain| domain["fqdn"] }
    assert_equal [ false, true, false ], domains.values_at("example.com", "example.org", "example.net").map { |domain| domain["autorenew"] }
    assert_equal [ true, true, false ], domains.values_at("example.com", "example.org", "example.net").map { |domain| domain["livedns"] }
    assert_equal [ "example.com" ], Integrations::Gandi.expiring_domains(@integration).map { |domain| domain["fqdn"] }, "example.org renews automatically"
    assert_equal 0, Activity.of_kind(:gandi_domain_expiring).count, "alert off"

    @integration.update!(settings: @integration.settings.merge("alert_expiring" => true))
    @integration.update_columns(state: {})
    assert_no_difference -> { Activity.of_kind(:gandi_domain_expiring).count } do
      sync
    end
    @integration.update!(settings: @integration.settings.merge("expiring_ignore_auto_renew" => false))
    assert_difference -> { Activity.of_kind(:gandi_domain_expiring).count }, 1 do
      sync
    end
    assert_equal "Domaine Gandi example.org : expire dans 10 jours", Activity.of_kind(:gandi_domain_expiring).last.summary
    assert_no_difference -> { Activity.of_kind(:gandi_domain_expiring).count } do
      sync
    end
  end

  test "test the connection, readable errors" do
    assert_equal "Connecté à Gandi : 3 domaines lisibles, 2 sur LiveDNS. Elio ne fait que lire : ne donnez au jeton que des droits de lecture.", Integrations::Gandi.test_connection(@integration)

    fake_gandi({ "/v5/livedns/domains" => ->(_) { raise Integrations::Error, I18n.t("integrations.http.forbidden", service: "Gandi", code: "401") } })
    assert_match "Gandi", assert_raises(Integrations::Error) { sync }.message

    fake_gandi({ "/v5/livedns/domains" => "<html>" })
    assert_match "Réponse inattendue de Gandi", assert_raises(Integrations::Error) { sync }.message
    fake_gandi({ "/v5/livedns/domains" => { "code" => 403, "message" => "Access was denied" }.to_json })
    assert_match "Réponse inattendue de Gandi", assert_raises(Integrations::Error) { sync }.message
  end

  test "without the right to list the domains, the DNS is still synced and the previous list kept" do
    sync
    fake_gandi({ "/v5/domain/domains" => ->(_) { raise Integrations::Error, "Gandi: accès refusé (403)" } })
    summary = sync
    assert_match "la liste des domaines n'a pas pu être lue : Gandi: accès refusé (403)", summary
    assert_equal 8, DnsRecord.of_source("gandi").count
    assert_equal 3, Integrations::Gandi.domains(@integration.reload).size
  end

  test "a domain name that is not one is never put in a URL" do
    fake_gandi({ "/v5/livedns/domains" => [ { "fqdn" => "../domain/domains" } ].to_json })
    assert_raises(Integrations::Error) { sync }
    assert @gandi_requests.none? { |url, _| url.include?("..") }
  end

  test "the settings page explains the token and lists the domains read" do
    sync
    assert_includes ApplicationController.render(partial: "integrations/gandi/help", locals: { integration: @integration.reload }), "example.net"
  end
end
