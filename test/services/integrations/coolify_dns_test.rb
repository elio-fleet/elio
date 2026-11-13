require "test_helper"

class Integrations::CoolifyDnsTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fake_coolify
    @integration = enable_coolify
    @integration.connections.first.sync!
    Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://dns.example.com" }, secrets: { "api_token" => "t" })
    Current.dns_sources = nil
    record("api.example.com", "A", "203.0.113.21", server: servers(:web))
    record("admin.example.com", "A", "198.51.100.99")
    record("old.example.com", "A", "203.0.113.21", server: servers(:web))
  end

  def record(name, type, value, server: nil)
    DnsRecord.create!(source: "technitium", source_id: "#{name}-#{type}", zone: "example.com", name: name, record_type: type, value: value, server: server)
  end

  def check = Integrations::Coolify::DomainCheck.new(servers(:web).reload)

  test "each domain served on the server against the DNS of the fleet" do
    states = check.domains.to_h { |domain| [ domain.name, domain.state ] }
    assert_equal({ "admin.example.com" => :elsewhere, "admin.example.dev" => :unknown, "api.example.com" => :ok, "n8n.example.com" => :missing }, states.sort.to_h)
    assert_equal [ "198.51.100.99" ], check.domains.find { |domain| domain.name == "admin.example.com" }.targets
    assert_equal %w[admin.example.com n8n.example.com], check.problems.map(&:name).sort
  end

  test "host: port and path dropped, wildcards and IPs skipped" do
    assert_equal "app.example.com", Integrations::Coolify::DomainCheck.host("App.Example.com:8080/api")
    assert_nil Integrations::Coolify::DomainCheck.host("*.example.com")
    assert_nil Integrations::Coolify::DomainCheck.host("203.0.113.5:3000")
  end

  test "health reasons, only with a DNS source and the alert on" do
    reasons = -> { Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).map(&:text).grep(/DNS/) }
    assert_equal [ "Coolify : admin.example.com est servi ici, mais son DNS pointe vers 198.51.100.99",
                   "Coolify : n8n.example.com est servi ici, mais n'a aucun enregistrement DNS" ], reasons.call
    reason = Integrations::Coolify.health_reasons(@integration, servers(:web)).find { |candidate| candidate.key.end_with?("dns_missing") }
    assert_equal [ "Voir le DNS", "/servers/#{servers(:web).id}?tab=dns" ], AttentionList.action_for(servers(:web), reason.to_h.stringify_keys)
    @integration.update!(settings: { "alert_dns" => false })
    assert_empty reasons.call

    @integration.update!(settings: {})
    Integration.find_by!(kind: "technitium").update!(enabled: false)
    Current.dns_sources = nil
    assert_empty reasons.call
  end

  test "the Coolify tab marks the domains whose DNS does not point here" do
    helper = Class.new(ActionView::Base) { include CoolifyHelper }.new(ActionView::LookupContext.new([]), {}, nil)
    html = helper.coolify_domain_links(CoolifyResource.find_by!(name: "back-office"), check: check)
    assert_includes html, 'data-dns="elsewhere"'
    assert_includes html, "Le DNS pointe vers 198.51.100.99, pas vers ce serveur"
    assert_includes helper.coolify_domain_links(CoolifyResource.find_by!(name: "api-facturation"), check: check), 'data-dns="ok"'
  end
end
