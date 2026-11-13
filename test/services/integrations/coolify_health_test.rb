require "test_helper"

class Integrations::CoolifyHealthTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    @integration = enable_coolify
    @connection = @integration.connections.first
  end

  def sync(**routes)
    fake_coolify("team_tools" => routes.transform_keys(&:to_s))
    @connection.reload.sync!
  end

  def reasons = Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).map(&:text)

  def resources_with(status:, last_online: 1.day.ago)
    fixture = JSON.parse(file_fixture("integrations/coolify/team_tools.json").read)["/resources"]
    fixture.map { |resource| resource["name"] == "n8n" ? resource.merge("status" => status, "last_online_at" => last_online.utc.strftime("%F %T")) : resource }
  end

  test "a stopped or unhealthy resource, unless stopped for long" do
    sync("/resources" => resources_with(status: "exited"))
    assert_includes reasons, "Coolify : n8n à l'arrêt (service)"
    sync("/resources" => resources_with(status: "running:unhealthy"))
    assert_includes reasons, "Coolify : n8n en mauvaise santé (service)"
    sync("/resources" => resources_with(status: "exited", last_online: 45.days.ago))
    assert_not reasons.any? { |text| text.include?("n8n") }, "stopped for 45 days: on purpose"

    sync("/resources" => resources_with(status: "exited"))
    @integration.update!(settings: { "alert_resources" => false })
    assert_not reasons.any? { |text| text.include?("n8n") }
  end

  test "a server Coolify can no longer reach or use is critical" do
    servers = JSON.parse(file_fixture("integrations/coolify/team_tools.json").read)["/servers"]
    sync("/servers" => servers.map { |server| server["name"] == "utils-1" ? server.merge("is_usable" => false) : server })
    reason = Integrations::Coolify.health_reasons(@integration.reload, servers(:web).reload).find { |candidate| candidate.key.end_with?("server_unreachable") }
    assert_equal [ "crit", "Coolify : ne peut plus joindre ou utiliser ce serveur (équipe Outils internes)" ], [ reason.tone, reason.text ]

    @integration.update!(settings: { "alert_server_unreachable" => false })
    assert_not reasons.any? { |text| text.include?("joindre") }
  end

  test "applications without a health check, only when chosen" do
    sync
    assert_not reasons.any? { |text| text.include?("health check") }
    @integration.update!(settings: { "alert_no_health_check" => true })
    assert_includes reasons, "Coolify : application back-office sans health check"
    assert_not reasons.any? { |text| text.include?("api-facturation sans") }, "it has one"
  end
end
