require "test_helper"

class Integrations::CoolifyKeysTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  KEY = CoolifyHelpers::COOLIFY_KEY
  FINGERPRINT = CoolifyHelpers::COOLIFY_FINGERPRINT

  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fake_coolify
    @integration = enable_coolify
    @integration.connections.first.sync!
  end

  def install(server, *lines) = AccountSnapshot.record!(server, AuthorizedKeysAccount.login(server), AuthorizedKey.parse(lines.join("\n")))

  test "the team's keys are read with their fingerprint, not the git deploy keys" do
    master, deploy = @integration.connections.first.reload.state["keys"]
    assert_equal({ "name" => "coolify-master", "fingerprint" => FINGERPRINT }, master)
    assert_equal [ "github-app-deploy", true ], deploy.values_at("name", "git")
    assert_not_equal FINGERPRINT, deploy["fingerprint"]
    assert_equal({ FINGERPRINT => { "source" => "Coolify", "name" => "coolify-master", "detail" => "équipe Outils internes · coolify.example.com" } }, Integration.known_keys)
  end

  test "Coolify's key is not outside the keyring" do
    install(servers(:web), KEY)
    assert_empty KeyInsights.new.orphans_by_server_id[servers(:web).id]
    assert_equal 0, Activity.of_kind(:unknown_key_detected).count
  end

  test "Coolify's key on a server Coolify does not manage, except the server hosting the instance" do
    install(servers(:db), KEY)
    reasons = -> { Integrations::Coolify.health_reasons(@integration.reload, servers(:db).reload) }
    reason = reasons.call.find { |candidate| candidate.key.end_with?("stale_key") }
    assert_equal "Coolify : la clé « coolify-master » (équipe Outils internes · coolify.example.com) est sur ce serveur, que Coolify ne gère pas", reason.text
    assert_equal [ "Voir les clés", "/servers/#{servers(:db).id}?tab=keys" ], AttentionList.action_for(servers(:db), reason.to_h.stringify_keys)

    install(servers(:web), KEY)
    assert_not Integrations::Coolify.health_reasons(@integration, servers(:web).reload).any? { |candidate| candidate.key.end_with?("stale_key") }, "managed by Coolify"

    servers(:db).update!(host: "coolify.example.com")
    assert_not reasons.call.any? { |candidate| candidate.key.end_with?("stale_key") }, "the Coolify host"

    servers(:db).update!(host: "db.example.com")
    @integration.update!(settings: { "alert_stale_key" => false })
    assert_empty reasons.call
  end
end
