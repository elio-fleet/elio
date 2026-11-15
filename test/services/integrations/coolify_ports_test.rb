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

  test "the databases inside a service: engine from the image, state, and critical once made public" do
    n8n = CoolifyResource.find_by!(name: "n8n")
    assert_equal [ { "name" => "postgresql", "engine" => "postgresql", "image" => "postgres:16-alpine", "status" => "exited" } ], n8n.service_databases
    assert_empty CoolifyResource.find_by!(name: "pg-facturation").service_databases
    assert_not Integrations::Coolify.health_reasons(@integration, servers(:web).reload).any? { |candidate| candidate.key.end_with?("public_database") }

    resources = JSON.parse(file_fixture("integrations/coolify/team_tools.json").read)["/resources"].map do |resource|
      next resource unless resource["name"] == "n8n"

      resource.merge("databases" => [ resource["databases"].first.merge("is_public" => true, "public_port" => 15432),
                                      { "name" => "redis", "image" => "registry.example.com:5000/library/redis:7@sha256:abc", "status" => "running:healthy", "is_public" => false, "public_port" => 6379 } ])
    end
    fake_coolify("team_tools" => { "/resources" => resources })
    @integration.connections.first.sync!
    assert_equal [ { "name" => "postgresql", "engine" => "postgresql", "image" => "postgres:16-alpine", "status" => "exited", "public" => true, "public_port" => 15432 },
                   { "name" => "redis", "engine" => "redis", "image" => "registry.example.com:5000/library/redis:7@sha256:abc", "status" => "running:healthy" } ], n8n.reload.service_databases
    reason = Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).find { |candidate| candidate.key.end_with?("public_database") }
    assert_equal [ "crit", "Coolify : la base n8n › postgresql est joignable depuis Internet (port 15432)" ], [ reason.tone, reason.text ]
    assert_equal "Service · PostgreSQL, Redis", ApplicationController.helpers.coolify_kind_detail(n8n)
  end

  test "servers running Coolify's proxy that no connection attaches: a team not connected" do
    proxy = [ { "name" => "coolify-proxy", "state" => "running" } ]
    [ servers(:web), servers(:db) ].each do |server|
      server.inventory_snapshots.create!(category: "docker", status: "ok", data: { "docker" => "ok", "containers" => proxy }, collected_at: Time.current, checked_at: Time.current)
    end
    servers(:backup).inventory_snapshots.create!(category: "docker", status: "ok", data: { "docker" => "ok", "containers" => [ { "name" => "nginx" } ] },
                                                 collected_at: Time.current, checked_at: Time.current)
    assert_equal [ servers(:db) ], Integrations::Coolify.unconnected_servers.to_a, "web is attached to utils-1; backup runs no proxy"
  end
end
