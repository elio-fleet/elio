require "test_helper"

# What a real Coolify 4.6.0 answers and the fixtures did not show (found on a
# local Coolify): placeholder git fields on an image application, "HEAD" as
# commit, domains served over plain HTTP, containers named after a uuid.
class Integrations::CoolifyRealInstanceTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers
  include PortHelpers

  IMAGE_APP = { "uuid" => "appimage00000000000000007", "name" => "status-page", "type" => "application", "build_pack" => "dockerimage",
                "fqdn" => "http://status.example.com", "git_repository" => "coollabsio/coolify", "git_branch" => "main", "git_commit_sha" => "HEAD",
                "docker_registry_image_name" => "nginx", "docker_registry_image_tag" => "1.27-alpine", "status" => "running:healthy",
                "destination" => { "server" => { "uuid" => "srvutils0000000000000001" } } }.freeze
  DEPLOYMENTS = { "count" => 1, "deployments" => [ { "deployment_uuid" => "depimage00000000000000001", "status" => "finished", "commit" => "HEAD",
                                                      "created_at" => "2026-11-13T17:12:15.000000Z", "finished_at" => "2026-11-13T17:12:40.000000Z" } ] }.freeze

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fixture = JSON.parse(file_fixture("integrations/coolify/team_tools.json").read)
    template = fixture["/resources"].find { |resource| resource["name"] == "api-facturation" }
    fake_coolify("team_tools" => { "/resources" => fixture["/resources"] + [ template.merge(IMAGE_APP) ],
                                   "/deployments/applications/#{IMAGE_APP["uuid"]}" => DEPLOYMENTS })
    @integration = enable_coolify
    @integration.connections.first.sync!
    @resource = CoolifyResource.find_by!(uuid: IMAGE_APP["uuid"])
  end

  test "an image application: no placeholder git fields, the image says what runs, no HEAD commit" do
    assert_nil @resource.data["git_repository"]
    assert_nil @resource.data["git_branch"]
    assert_nil @resource.data["git_commit"]
    assert_equal "nginx:1.27-alpine", ApplicationController.helpers.coolify_version(@resource)
    assert_nil @resource.data["deployments"].first["commit"]
  end

  test "a git application keeps its branch, and HEAD is not a commit" do
    back_office = CoolifyResource.find_by!(name: "back-office")
    assert_equal [ "main", nil ], back_office.data.values_at("git_branch", "git_commit")
  end

  test "the monitors prompt keeps the scheme Coolify serves a domain with" do
    text = ServerPrompt.new(servers(:web).reload).monitors
    assert_includes text, "- http://status.example.com (status-page, application, running)"
    assert_includes text, "- http://admin.example.dev (back-office"
    assert_includes text, "- https://api.example.com (api-facturation"
  end

  test "containers are named after their Coolify resource in the prompts and the ufw rules" do
    record_ports(servers(:web))
    record_containers(servers(:web), [ { "name" => "#{IMAGE_APP["uuid"]}-20261113T171215", "image" => "nginx:1.27-alpine", "state" => "running",
                                         "ports" => "0.0.0.0:8080->80/tcp", "project" => IMAGE_APP["uuid"] } ])
    server = servers(:web).reload

    assert_match %r{^- #{IMAGE_APP["uuid"]}-20261113T171215, .*, Coolify : status-page \(application\)$}, ServerPrompt.new(server).monitors
    analysis = Inventory::PortAnalysis.new(server)
    assert_equal "Coolify status-page", analysis.send(:container_label, "#{IMAGE_APP["uuid"]}-20261113T171215")
    assert_equal "coolify-proxy", analysis.send(:container_label, "coolify-proxy")
  end
end
