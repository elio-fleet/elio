require "test_helper"

class Integrations::CoolifyPortsTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers
  include PortHelpers

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fake_coolify
    @integration = enable_coolify
    @integration.connections.first.sync!
  end

  test "the resource behind a container" do
    resources = servers(:web).coolify_resources.to_a
    assert_equal "api-facturation", CoolifyResource.for_container(resources, "name" => "appapi000000000000000001-20261108T120000").name
    assert_equal "n8n", CoolifyResource.for_container(resources, "name" => "postgresql-svcn8n0000000000000000003").name
    assert_equal "back-office", CoolifyResource.for_container(resources, "name" => "web-1", "project" => "appback000000000000000002").name
    assert_nil CoolifyResource.for_container(resources, "name" => "coolify-proxy")
  end

  test "the firewall prompt says which Coolify resource publishes a port" do
    record_ports(servers(:web))
    record_containers(servers(:web), [ { "name" => "n8n-svcn8n0000000000000000003", "state" => "running", "ports" => "0.0.0.0:9100->5678/tcp" } ])
    assert_match %r{^- 9100/tcp .*conteneur n8n-svcn8n0000000000000000003, Coolify : n8n \(service\)}, ServerPrompt.new(servers(:web).reload).firewall
  end

  test "a database made public in Coolify is critical, if chosen" do
    resources = JSON.parse(file_fixture("integrations/coolify/team_tools.json").read)["/resources"]
    fake_coolify("team_tools" => { "/resources" => resources.map { |resource| resource["name"] == "pg-facturation" ? resource.merge("is_public" => true, "public_port" => 5433) : resource } })
    @integration.connections.first.sync!
    reason = Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).find { |candidate| candidate.key.end_with?("public_database") }
    assert_equal [ "crit", "Coolify : la base pg-facturation est joignable depuis Internet (port 5433)" ], [ reason.tone, reason.text ]

    @integration.update!(settings: { "alert_public_database" => false })
    assert_not Integrations::Coolify.health_reasons(@integration.reload, servers(:web)).any? { |candidate| candidate.key.end_with?("public_database") }
  end
end
