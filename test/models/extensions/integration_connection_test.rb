require "test_helper"

class IntegrationConnectionTest < ActiveSupport::TestCase
  include IntegrationHelpers

  setup { Integration.registry = { "demo" => "DemoIntegration", "demo_multi" => "DemoMultiIntegration" } }
  teardown { Integration.registry = nil }

  test "values of the connection fields, a blank secret kept, secrets encrypted" do
    connection = enable_demo_multi("https://one.example/team-alpha").connections.first
    assert_equal [ "https://one.example/team-alpha", "secret-token" ], [ connection.value(:url), connection.value(:token) ]
    assert_raises(ArgumentError) { connection.value(:alert) }

    connection.assign_form("url" => "https://two.example", "token" => "")
    assert_equal [ "https://two.example", "secret-token" ], [ connection.value(:url), connection.value(:token) ]

    raw = IntegrationConnection.connection.select_value("SELECT secrets FROM integration_connections WHERE id = #{connection.id}")
    assert_not_includes raw, "secret-token"
  end

  test "required fields and URLs checked, the name optional" do
    integration = enable_demo_multi
    connection = integration.connections.build
    assert_not connection.valid?
    assert_equal [ "URL : obligatoire", "Jeton : obligatoire" ], connection.errors.full_messages

    connection.assign_form("url" => "ftp://nope", "token" => "x")
    assert_not connection.valid?
    assert_match "adresse http(s) attendue", connection.errors.full_messages.to_sentence

    connection.assign_form("url" => "https://ok.example")
    connection.name = "   "
    assert connection.valid?
    assert_nil connection.name
  end

  test "label: the name, else what the service says, else a number; group from the definition" do
    connection = enable_demo_multi("https://coolify.example/team-alpha").connections.first
    assert_equal "Connexion n° #{connection.id}", connection.label
    connection.sync!
    assert_equal [ "team-alpha", "coolify.example" ], [ connection.label, connection.group ]
    connection.update!(name: "Production")
    assert_equal "Production", connection.label
  end

  test "sync! remembers the date or the error, logged once" do
    connection = enable_demo_multi("https://bad.example").connections.first
    2.times { assert_raises(Integrations::Error) { connection.sync! } }
    assert_equal "refusé (401)", connection.reload.last_error
    assert_equal 1, Activity.of_kind(:integration_sync_failed).count
    assert_equal "Synchronisation Démo multiple · Connexion n° #{connection.id} impossible : refusé (401)", Activity.of_kind(:integration_sync_failed).first.summary

    connection.update!(settings: { "url" => "https://ok.example/team-beta" })
    assert_equal "2 éléments", connection.sync!
    assert_nil connection.reload.last_error
    assert connection.last_synced_at
  end

  test "the extension syncs each connection: fails only when all fail" do
    integration = enable_demo_multi("https://a.example/team-a", "https://bad.example")
    summary = integration.sync!
    assert_equal "team-a : 2 éléments · Connexion n° #{integration.connections.last.id} : échec (refusé (401))", summary
    assert_nil integration.reload.last_error

    integration.connections.first.update!(settings: { "url" => "https://bad.example" })
    error = assert_raises(Integrations::Error) { integration.sync! }
    assert_match "refusé (401)", error.message
    assert integration.reload.last_error
  end

  test "an extension with no connection yet" do
    assert_equal "aucune connexion", enable_demo_multi.sync!
  end

  test "deleting the extension or a connection" do
    integration = enable_demo_multi("https://a.example")
    assert_difference -> { IntegrationConnection.count }, -1 do
      integration.destroy!
    end
  end

  test "single-connection extensions are not affected" do
    assert_not DemoIntegration.multiple_connections?
    assert DemoMultiIntegration.multiple_connections?
    assert_equal "3 éléments", enable_demo.sync!
  end
end
