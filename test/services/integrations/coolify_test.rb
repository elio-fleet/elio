require "test_helper"

class Integrations::CoolifyTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  setup do
    fake_coolify
    servers(:web).update!(extra_addresses_text: "203.0.113.21")            # utils-1, by address
    servers(:db).update!(name: "tiles-fr", host: "198.51.100.30")         # TILES-FR: its address in Coolify is a host name
    servers(:backup).update!(host: "coolify.example.com")                 # the server hosting Coolify, by the instance's host name
  end

  test "reads with GET and a Bearer token under /api/v1, never the token in the URL" do
    enable_coolify.sync!
    assert @coolify_requests.any?
    @coolify_requests.each do |url, options|
      assert url.start_with?("https://coolify.example.com/api/v1/"), url
      assert_not_includes url, "tok-"
      assert_equal "Bearer tok-tools", options.dig(:headers, "Authorization")
    end
  end

  test "test_connection: the team, the version and the servers; warns about a token that reads secrets" do
    connection = enable_coolify.connections.first
    assert_equal "équipe « Outils internes », Coolify v4.6.0, 3 serveurs", Integrations::Coolify.test_connection(connection)

    fake_coolify("team_tools" => { "/security/keys" => [ { "name" => "k", "private_key" => "-----BEGIN OPENSSH PRIVATE KEY-----" } ] })
    assert_match "lit aussi les secrets", Integrations::Coolify.test_connection(connection)

    connection.secrets = { "token" => "wrong" }
    error = assert_raises(Integrations::Error) { Integrations::Coolify.test_connection(connection) }
    assert_match "401", error.message
  end

  test "the servers attached by address, host name or name, the Coolify host by the instance's host name" do
    connection = enable_coolify.connections.first
    connection.sync!
    servers = CoolifyResource.servers.index_by(&:name)
    assert_equal [ servers(:web), "address" ], [ servers["utils-1"].server, servers["utils-1"].matched_by ]
    assert_equal [ servers(:db), "host" ], [ servers["TILES-FR"].server, servers["TILES-FR"].matched_by ]
    assert_equal [ servers(:backup), "instance" ], [ servers["localhost"].server, servers["localhost"].matched_by ]
    assert_equal({ "ip" => "203.0.113.21", "user" => "root", "port" => 22, "reachable" => true, "usable" => true, "coolify_host" => false, "build_server" => false,
                   "docker_version" => "29.9.2", "proxy" => "TRAEFIK", "domains" => %w[admin.example.com api.example.com n8n.example.com] }, servers["utils-1"].data)
  end

  test "the resources with their server, project, environment and domains; unknown kinds skipped; no secret kept" do
    enable_coolify.connections.first.sync!
    resources = CoolifyResource.resources.index_by(&:name)
    assert_equal %w[api-facturation back-office n8n pg-facturation tiles], resources.keys.sort

    api = resources["api-facturation"]
    assert_equal [ "application", "running:healthy", servers(:web) ], [ api.kind, api.status, api.server ]
    assert_equal({ "type" => "application", "restart_count" => 0, "last_online_at" => "2026-11-08 12:50:09", "project" => "Facturation", "environment" => "production",
                   "build_pack" => "dockerfile", "domains" => [ "api.example.com" ], "git_repository" => "acme/api-facturation", "git_branch" => "main",
                   "git_commit" => "623a4be", "health_check" => true, "health_check_path" => "/up", "ports_exposes" => "3000" }, api.data)
    assert_equal %w[admin.example.com admin.example.dev], resources["back-office"].domains

    n8n = resources["n8n"]
    assert_equal [ "service", "Outils", servers(:web), [ "n8n.example.com" ], %w[n8nio/n8n:1.82 postgres:16-alpine] ], [ n8n.kind, n8n.data["project"], n8n.server, n8n.domains, n8n.data["images"] ]
    assert n8n.stopped?

    pg = resources["pg-facturation"]
    assert_equal [ "database", "postgresql", false ], [ pg.kind, pg.data["engine"], pg.data["public"] ]
    assert_equal [ servers(:db), "staging" ], [ resources["tiles"].server, resources["tiles"].data["environment"] ]
    assert_not CoolifyResource.pluck(:data).to_s.include?("docker_compose_raw")
  end

  test "states and health read from the status" do
    resource = CoolifyResource.new(status: "running:unhealthy")
    assert [ resource.running?, resource.unhealthy?, resource.stopped? ] == [ true, true, false ]
    assert_equal [ "exited", nil ], [ CoolifyResource.new(status: "exited").state, CoolifyResource.new(status: "exited").health ]
  end

  test "a sync replaces the connection's resources, the connection remembers its team" do
    connection = enable_coolify.connections.first
    connection.sync!
    assert_equal [ "Outils internes", "4.6.0", 3, 3, 5 ], connection.reload.state.values_at("team", "version", "servers", "attached", "resources")
    assert_equal "Outils internes", connection.label
    assert_equal "coolify.example.com", connection.group
    assert_equal "3 serveurs dont 3 dans le parc · 5 ressources · Coolify v4.6.0", Integrations::Coolify.connection_summary(connection)

    fake_coolify("team_tools" => { "/resources" => [] })
    assert_equal "3 serveurs (3 dans le parc), 0 ressources", connection.sync!
    assert_equal 0, CoolifyResource.resources.count
  end

  test "one connection per team: each keeps its own resources, deleting one removes them" do
    integration = enable_coolify("tok-tools", "tok-maps")
    assert_match "Outils internes : 3 serveurs", integration.sync!
    assert_equal %w[Cartographie Outils\ internes], integration.connections.map(&:label).sort
    atlas = CoolifyResource.find_by!(name: "atlas")
    assert_nil atlas.server, "gis-1 is not in the fleet"

    integration.connections.find { |connection| connection.label == "Cartographie" }.destroy!
    assert_not CoolifyResource.exists?(atlas.id)
    assert_equal 8, CoolifyResource.count
  end

  test "a server deleted from the fleet leaves its Coolify resources unattached" do
    enable_coolify.connections.first.sync!
    servers(:web).destroy!
    assert_nil CoolifyResource.find_by!(name: "api-facturation").server_id
  end

  test "an unexpected answer is an error, a uuid is checked before going into a path" do
    fake_coolify("team_tools" => { "/servers" => { "message" => "nope" } })
    error = assert_raises(Integrations::Error) { enable_coolify.connections.first.sync! }
    assert_match "Réponse inattendue de Coolify", error.message

    client = Integrations::Coolify::Client.new(url: "https://coolify.example.com", token: "tok-tools")
    assert_raises(Integrations::Error) { client.server_domains("../../etc") }
  end
end
