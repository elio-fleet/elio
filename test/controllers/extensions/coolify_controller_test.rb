require "test_helper"

class CoolifyControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include CoolifyHelpers
  include PortHelpers

  setup do
    sign_in users(:viewer)
    fake_coolify
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    @integration = enable_coolify("tok-tools", "tok-maps")
    @integration.sync!
  end

  test "404 while the extension is off" do
    @integration.update!(enabled: false)
    get coolify_path
    assert_response :not_found
  end

  test "every resource of every team, what needs attention first, with its server" do
    get coolify_path
    assert_response :success
    assert_select "h1", "Coolify"
    names = css_select("#coolify-resources tr.coolify-resource td:first-child span.font-medium").map(&:text)
    assert_equal "n8n", names.first, "the stopped service first"
    assert_equal %w[api-facturation atlas back-office n8n pg-facturation tiles].sort, names.sort
    assert_select "tr.coolify-resource[data-uuid=appapi000000000000000001]" do
      assert_select ".server-chip", "Web"
      assert_select ".coolify-state[data-state=healthy]"
      assert_select "a[href='https://api.example.com']"
    end
    assert_select "tr.coolify-resource[data-uuid=appatlas00000000000000001]", text: /hors du parc/
    assert_select "#stat-coolify-attention", text: /1/
    assert_select "#stat-coolify-unattached", text: /2/
  end

  test "filters and search" do
    get coolify_path(filter: "attention")
    assert_equal [ "n8n" ], css_select("tr.coolify-resource td:first-child span.font-medium").map(&:text)
    get coolify_path(filter: "databases")
    assert_equal [ "pg-facturation" ], css_select("tr.coolify-resource td:first-child span.font-medium").map(&:text)
    get coolify_path(q: "admin.example")
    assert_equal [ "back-office" ], css_select("tr.coolify-resource td:first-child span.font-medium").map(&:text)
    get coolify_path(q: "nothing-like-it")
    assert_select ".empty-state", text: /Aucune ressource/
  end

  test "a failed connection is said in the subtitle" do
    @integration.connections.last.update!(last_error: "refusé")
    get coolify_path
    assert_select "header", text: /Connexion en échec : Cartographie/
  end

  test "the Coolify tab of a managed server, absent elsewhere" do
    get server_path(servers(:web), tab: "coolify")
    assert_select ".server-tabs a", text: /Coolify\s*4/
    assert_select "#server-coolify .coolify-server" do
      assert_select "[data-status=team]", text: /Outils internes/
      assert_select "[data-status=reachable]", text: /joignable/
    end
    assert_select "#coolify-resources tr.coolify-resource", 4
    assert_select "tr.coolify-resource[data-uuid=appback000000000000000002]" do
      assert_select "td", text: "Facturation / production"
      assert_select ".coolify-state[data-state=running]"
    end
    assert_select "tr.coolify-resource[data-uuid=appapi000000000000000001] td.font-mono", "main @ 623a4be"
    assert_select "tr.coolify-resource[data-uuid=appback000000000000000002] td.font-mono", "main"
    assert_select "#coolify-resources", text: /pas de health check/
    assert_select "tr.coolify-resource[data-uuid=appapi000000000000000001] .coolify-domain[data-dns]", 0, "no DNS source: not checked"
    assert_select "tr.coolify-resource[data-uuid=appapi000000000000000001] a[href=?]",
                  "https://coolify.example.com/project/projbilling00000000000001/environment/envprod0000000000000001/application/appapi000000000000000001", text: "api-facturation"
    assert_select "tr.coolify-resource[data-uuid=appback000000000000000002] .deploy-failed", "échec"
    assert_equal %w[failed finished failed], css_select("#coolify-deployments li.coolify-deployment").map { |item| item["data-status"] }
    assert_select "#coolify-deployments li.coolify-deployment", text: /chore: 0.5.15.*webhook git/m
    assert_select "#coolify-backups li.coolify-backup[data-uuid=dbpg000000000000000000004][data-state=late]" do
      assert_select ".backup-state", "en retard"
      assert_equal %w[success failed success], css_select(".backup-execution").map { |square| square["data-status"] }
    end

    get server_path(servers(:backup))
    assert_select ".server-tabs a", text: /Coolify/, count: 0
  end

  test "the Docker tab names the containers after their Coolify resource" do
    containers = [ { "name" => "appapi000000000000000001-20261108T120000", "state" => "running" },
                   { "name" => "postgresql-svcn8n0000000000000000003", "state" => "exited" },
                   { "name" => "web-appback000000000000000002-0451", "project" => "appback000000000000000002", "service" => "web", "state" => "running" },
                   { "name" => "coolify-proxy", "state" => "running" } ]
    servers(:web).inventory_snapshots.create!(category: "docker", status: "ok", data: { "docker" => "ok", "containers" => containers, "images" => [] },
                                              collected_at: Time.current, checked_at: Time.current)
    get server_path(servers(:web), tab: "docker")
    assert_select "tr.docker-container-row[data-name=appapi000000000000000001-20261108T120000] .coolify-container", "api-facturation"
    assert_select "tr.docker-container-row[data-name=postgresql-svcn8n0000000000000000003] .coolify-container", "n8n › postgresql"
    assert_select "tr.docker-container-row[data-name=web-appback000000000000000002-0451] .coolify-container", "back-office › web"
    assert_select "tr.docker-container-row[data-name=coolify-proxy] .coolify-container", 0
  end

  test "the Firewall tab and the Ports page name the Coolify resource that publishes a port" do
    record_ports(servers(:web))
    record_containers(servers(:web), [ { "name" => "n8n-svcn8n0000000000000000003", "state" => "running", "ports" => "0.0.0.0:9100->5678/tcp" } ])
    get server_path(servers(:web), tab: "firewall")
    assert_select ".coolify-port-owner[title=n8n-svcn8n0000000000000000003]", "n8n"
    get ports_path
    assert_select ".coolify-port-owner", "n8n"
  end
end
