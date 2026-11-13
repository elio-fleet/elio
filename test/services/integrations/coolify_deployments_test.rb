require "test_helper"

class Integrations::CoolifyDeploymentsTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  API = "/deployments/applications/appapi000000000000000001".freeze

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fake_coolify
    @integration = enable_coolify
    @connection = @integration.connections.first
  end

  def api = CoolifyResource.find_by!(name: "api-facturation")

  def deployment(uuid, status, at: 1.hour.ago, commit: "abc1234def", message: "feat: x")
    { "deployment_uuid" => uuid, "status" => status, "commit" => commit, "commit_message" => message, "created_at" => at.iso8601, "finished_at" => at.iso8601,
      "deployment_url" => "/project/p1/environment/e1/application/appapi000000000000000001/deployment/#{uuid}" }
  end

  test "the last deployments are kept: first line of the message, the application's page in Coolify" do
    @connection.sync!
    assert_equal({ "uuid" => "dep0000000000000000000002", "status" => "finished", "commit" => "623a4be87f327f1bdba283631e4747cc83c4a19", "message" => "chore: 0.5.15",
                   "at" => "2026-11-06T09:21:57.000000Z", "finished_at" => "2026-11-06T09:23:31.000000Z", "webhook" => true }, api.deployments.first)
    assert_equal "/project/projbilling00000000000001/environment/envprod0000000000000001/application/appapi000000000000000001", api.data["coolify_path"]
    assert_equal "finished", api.last_deployment["status"]
    assert_not api.deploy_failed?
    assert CoolifyResource.find_by!(name: "back-office").deploy_failed?
    assert @coolify_requests.any? { |url, _| url.end_with?("#{API}?skip=0&take=10") }
  end

  test "a failed last deployment is a health reason until the next success, if chosen" do
    @connection.sync!
    reasons = -> { Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).map(&:text) }
    assert_includes reasons.call, "Coolify : déploiement de back-office en échec"
    assert_not reasons.call.any? { |text| text.include?("api-facturation") }

    @integration.update!(settings: { "alert_deploy_failed" => false })
    assert_not reasons.call.any? { |text| text.include?("déploiement") }
  end

  test "deployments that ended since the last sync go to the server's journal, never on the first sync" do
    @connection.sync!
    assert_equal 0, Activity.where(kind: %w[coolify_deployed coolify_deploy_failed]).count

    running = deployment("dep-new", "in_progress")
    fake_coolify("team_tools" => { API => { "count" => 3, "deployments" => [ running ] } })
    @connection.sync!
    assert_equal 0, Activity.where(kind: %w[coolify_deployed coolify_deploy_failed]).count, "still running"

    fake_coolify("team_tools" => { API => { "count" => 4, "deployments" => [ deployment("dep-newer", "failed", message: "fix: y\nbody"), deployment("dep-new", "finished", at: 2.hours.ago) ] } })
    @connection.sync!
    assert_equal [ "Coolify : api-facturation déployée (abc1234 « feat: x »)", "Coolify : déploiement de api-facturation en échec (abc1234 « fix: y »)" ],
                 Activity.where(kind: %w[coolify_deployed coolify_deploy_failed]).order(:id).map(&:summary)
    assert Activity.where(kind: "coolify_deployed").all? { |activity| activity.server == servers(:web) }

    @connection.sync!
    assert_equal 2, Activity.where(kind: %w[coolify_deployed coolify_deploy_failed]).count, "logged once"
  end
end
