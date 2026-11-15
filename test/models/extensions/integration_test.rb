require "test_helper"

class IntegrationTest < ActiveSupport::TestCase
  include IntegrationHelpers
  include StubHelpers

  setup { Integration.registry = { "demo" => "DemoIntegration" } }
  teardown { Integration.registry = nil }

  test "values: setting, secret or default" do
    integration = enable_demo
    assert_equal "https://demo.example", integration.value(:url)
    assert_equal "secret-key", integration.value(:api_key)
    assert_equal true, integration.value(:verify_ssl)
    assert_equal %w[ip], integration.value(:products)
    assert_raises(ArgumentError) { integration.value(:nope) }
  end

  test "secrets are encrypted in the database" do
    integration = enable_demo
    raw = Integration.connection.select_value("SELECT secrets FROM integrations WHERE id = #{integration.id}")
    assert_not_includes raw, "secret-key"
    assert_equal "secret-key", Integration.find(integration.id).secrets["api_key"]
  end

  test "assign_form casts the values and keeps a blank secret" do
    integration = enable_demo
    integration.assign_form("url" => " https://other.example ", "api_key" => "", "verify_ssl" => "0", "products" => [ "", "dns", "evil" ], "threshold" => "7")
    assert_equal [ "https://other.example", "secret-key", false, %w[dns], 7 ], %i[url api_key verify_ssl products threshold].map { |key| integration.value(key) }

    integration.assign_form("api_key" => "new-key")
    assert_equal "new-key", integration.value(:api_key)
    assert_equal false, integration.value(:alert), "an unchecked box is false"
  end

  test "required fields only to enable it" do
    integration = Integration.new(kind: "demo")
    assert integration.valid?
    integration.enabled = true
    assert_not integration.valid?
    assert_equal [ "URL : obligatoire pour activer l'extension", "Clé API : obligatoire pour activer l'extension" ], integration.errors.full_messages
  end

  test "URL fields must be http(s)" do
    integration = enable_demo
    integration.assign_form("url" => "javascript:alert(1)")
    assert_not integration.valid?
    assert_equal [ "URL : adresse http(s) attendue (ex. https://uptime.example.com)" ], integration.errors.full_messages
    assert Integration.http_url?("https://demo.example/path")
    assert_not Integration.http_url?("ftp://demo.example")
  end

  test "unknown kind" do
    assert_not Integration.new(kind: "nope").valid?
  end

  test "registry helpers: all kinds, enabled ones, tabs, links and health reasons" do
    assert_equal [ "demo" ], Integration.all_kinds.map(&:kind)
    assert_not Integration.enabled?(:demo)
    assert_empty Integration.server_tabs

    integration = enable_demo(alert: true)
    assert Integration.enabled?(:demo)
    assert_equal [ "demo" ], Integration.server_tabs.map { |tab| tab[:key] }
    assert_equal integration, Integration.server_tabs.first[:integration]
    assert_equal [ "Démo" ], Integration.sidebar_links.map { |link| link[:label] }
    assert_equal [ "Alerte de démonstration" ], Integration.health_reasons(servers(:web)).map(&:text)

    Integration.registry = {}
    assert_not Integration.enabled?(:demo), "a kind no longer registered is never enabled"
  end

  test "sync! remembers the date, or the error logged once" do
    integration = enable_demo
    assert_equal "3 éléments", integration.sync!
    assert integration.last_synced_at
    assert_nil integration.last_error

    integration.update!(settings: integration.settings.merge("url" => "https://bad.example"))
    2.times { assert_raises(Integrations::Error) { integration.sync! } }
    assert_equal "refusé (401)", integration.reload.last_error
    assert_equal 1, Activity.of_kind(:integration_sync_failed).count

    integration.update!(settings: integration.settings.merge("url" => "https://demo.example"))
    integration.sync!
    assert_nil integration.reload.last_error
  end

  test "enqueue_sync! creates a followed task" do
    integration = enable_demo
    task = integration.enqueue_sync!(user: users(:one))
    assert_equal [ "integration", "Synchronisation Démo", "queued" ], [ task.kind, task.label, task.status ]
  end

  test "manual links" do
    integration = enable_demo
    integration.links.create!(external_id: "73", server: servers(:web))
    integration.links.create!(external_id: "74", server: nil)
    assert_equal({ "73" => servers(:web).id, "74" => nil }, integration.manual_links)
    assert_not integration.links.build(external_id: "73").valid?
  end

  test "sync! remembers how long the sync took" do
    integration = enable_demo
    integration.sync!
    assert_kind_of Integer, integration.reload.last_sync_duration_ms
    assert_operator integration.last_sync_duration_ms, :>=, 0
  end

  test "an API key about to expire is logged once, again for a new key, never when far or unknown" do
    integration = enable_demo
    expires = 10.days.from_now.change(usec: 0)
    stub_method(DemoIntegration, :credential_expires_at, ->(_integration) { expires }) do
      2.times { integration.sync! }
      assert_equal expires, integration.reload.credential_expires_at
      assert integration.credential_expiring?
      activity = Activity.of_kind(:integration_credential_expiring).sole
      assert_equal "Clé d'API Démo : expire dans 10 jours (#{I18n.l(expires.to_date, format: :long)})", activity.summary

      expires = 9.days.from_now.change(usec: 0)
      integration.sync!
      assert_equal 2, Activity.of_kind(:integration_credential_expiring).count, "a new key is announced again"

      expires = 1.year.from_now.change(usec: 0)
      integration.sync!
      assert_not integration.reload.credential_expiring?
      assert_not integration.credential_expiry_logged?
      assert_equal 2, Activity.of_kind(:integration_credential_expiring).count
    end

    stub_method(DemoIntegration, :credential_expires_at, ->(_integration) { raise Integrations::Error, "refusé" }) do
      assert_equal "3 éléments", integration.sync!, "a key that cannot be read does not fail the sync"
      assert_nil integration.reload.last_error
    end
  end

  test "purge_data! deletes what the syncs stored, only while off, and logs it" do
    integration = enable_demo
    integration.sync!
    integration.update_columns(state: { "seen" => [ 1 ] }, credential_expires_at: 3.days.from_now)
    purged = []
    stub_method(DemoIntegration, :purge, ->(record) { purged << record.kind }) do
      assert_not integration.purge_data!(user: users(:one)), "refused while on"
      assert_empty purged

      integration.update!(enabled: false)
      assert integration.stored_data?
      assert integration.purge_data!(user: users(:one))
    end
    assert_equal [ "demo" ], purged
    integration.reload
    assert_equal [ {}, nil, nil, nil ], [ integration.state, integration.last_synced_at, integration.last_sync_duration_ms, integration.credential_expires_at ]
    assert_equal "https://demo.example", integration.value(:url), "the settings stay"
    assert_not integration.stored_data?
    activity = Activity.of_kind(:integration_data_deleted).sole
    assert_equal [ "Données de l'extension Démo supprimées", users(:one) ], [ activity.summary, activity.user ]
  end
end
