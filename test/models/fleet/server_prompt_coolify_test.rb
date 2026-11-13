require "test_helper"

class ServerPromptCoolifyTest < ActiveSupport::TestCase
  include StubHelpers
  include CoolifyHelpers

  test "the monitors prompt lists the Coolify domains, their health check and the probe that watches each" do
    servers(:web).update!(extra_addresses_text: "203.0.113.21")
    fake_coolify
    enable_coolify.connections.first.sync!
    UptimeKumaMonitor.create!(monitor_id: "9", name: "API", monitor_type: "http", url: "https://api.example.com/up", status: 1, server: servers(:backup))

    text = ServerPrompt.new(servers(:web).reload).monitors
    assert_includes text, "## Domaines servis par Coolify sur ce serveur"
    assert_includes text, "- https://api.example.com (api-facturation, application, running) — health check Coolify : /up — sonde existante : API"
    assert_includes text, "- https://admin.example.com (back-office, application, running) — pas de health check dans Coolify — aucune sonde"
    assert_includes text, "- https://n8n.example.com (n8n, service, exited) — aucune sonde"
    assert_not_includes ServerPrompt.new(servers(:db)).monitors, "Coolify"
  end
end
