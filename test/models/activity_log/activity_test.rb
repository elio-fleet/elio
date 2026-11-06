require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  teardown { Current.reset }

  test "every kind has a summary, and only those" do
    assert_equal Activity::KINDS.keys.sort, Activity::Summaries::BY_KIND.keys.sort
  end

  test "every kind has a label, a known category and a known severity" do
    Activity::KINDS.each_value do |kind|
      assert kind.label.present?, kind.key
      assert kind.description.present?, kind.key
      assert_includes Activity::CATEGORIES, kind.category, kind.key
      assert_includes Activity::SEVERITIES, kind.severity, kind.key
    end
  end

  test "rejects an unknown kind" do
    assert_not Activity.new(kind: "nope").valid?
    assert_raises(ActiveRecord::RecordInvalid) { Activity.record!(:nope) }
  end

  test "record! copies names and defaults the author to the current user" do
    Current.user = users(:one)

    activity = Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", key_name: "alice@laptop")

    assert_equal users(:one), activity.user
    assert_equal "one@example.com", activity.author_name
    assert_equal({ "key_name" => "alice@laptop", "server_name" => "Web", "public_key_name" => "Alice" }, activity.data)
    assert_equal "Clé ajoutée", activity.label
    assert_equal :keys, activity.category
    assert_equal :info, activity.severity
  end

  test "without a current user the author is the system" do
    assert_equal "Système", Activity.record!(:server_unreachable, server: servers(:web)).author_name
  end

  test "stays readable once the server and the public_key are deleted" do
    activity = Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy")
    public_keys(:alice).destroy!
    servers(:web).destroy!

    activity.reload
    assert_nil activity.server
    assert_equal "« Alice » ajoutée sur « Web »", activity.summary
  end

  test "summaries" do
    web = servers(:web)
    {
      [ :key_added, { public_key: public_keys(:alice), unix_user: "deploy", duration_label: "10 minutes" } ] => "« Alice » ajoutée sur « Web » pendant 10 minutes",
      [ :key_removed, { unix_user: "deploy", key_name: "bob" } ] => "Clé « bob » supprimée de « Web »",
      [ :key_removed, { unix_user: "root", key_name: "bob" } ] => "Clé « bob » supprimée de « Web » (compte root)",
      [ :key_expired, { public_key: public_keys(:ci), unix_user: "deploy" } ] => "Accès temporaire de « CI » retiré de « Web »",
      [ :unknown_key_detected, { unix_user: "root" } ] => "Clé inconnue « sans nom » trouvée sur « Web » (compte root)",
      [ :key_disappeared, { unix_user: "root", key_name: "bob" } ] => "Clé « bob » disparue de « Web » (compte root)",
      [ :ssh_access_lost, {} ] => "« Web » refuse la clé d'Elio",
      [ :servers_imported, { count: 12, format: "CSV", names: %w[A B] } ] => "12 serveurs importés (CSV) : A, B…",
      [ :server_group_created, { group_name: "Prod", servers: 2 } ] => "Groupe « Prod » créé (2 serveurs)",
      [ :server_group_deleted, { group_name: "Prod" } ] => "Groupe « Prod » supprimé",
      [ :host_key_changed, { new_fingerprint: "SHA256:new" } ] => "Nouvelle empreinte acceptée pour « Web » : SHA256:new",
      [ :server_unreachable, {} ] => "« Web » ne répond plus",
      [ :server_back_online, {} ] => "« Web » répond à nouveau",
      [ :os_upgraded, { from: "Debian 11", to: "Debian 12" } ] => "« Web » est passé de Debian 11 à Debian 12",
      [ :server_rebooted, {} ] => "« Web » a redémarré",
      [ :health_warning, { reasons: [ "Redémarrage requis", "Mémoire à 92 %" ] } ] => "« Web » est à surveiller : Redémarrage requis, Mémoire à 92 %",
      [ :health_recovered, {} ] => "« Web » est de nouveau sain",
      [ :packages_changed, { installed: 2, upgraded: 1, removed: 0, examples: [ "curl" ] } ] => "Paquets de « Web » : 2 installés, 1 mis à jour (curl)",
      [ :security_updates_available, { count: 3 } ] => "3 mises à jour de sécurité disponibles sur « Web »",
      [ :service_failed, { service: "nginx.service" } ] => "nginx.service est en échec sur « Web »",
      [ :container_stopped, { container: "pgbouncer" } ] => "Le conteneur pgbouncer s'est arrêté sur « Web »",
      [ :port_opened, { port: "3306/tcp", process: "mariadbd" } ] => "Port 3306/tcp ouvert publiquement sur « Web » (mariadbd)",
      [ :port_closed, { port: "8080/tcp" } ] => "Port 8080/tcp fermé sur « Web »",
      [ :server_created, {} ] => "Serveur « Web » ajouté",
      [ :server_updated, {} ] => "Serveur « Web » modifié"
    }.each do |(kind, options), summary|
      assert_equal summary, Activity.record!(kind, server: web, **options).summary, kind
    end

    assert_equal "Clé « Alice » ajoutée au trousseau", Activity.record!(:public_key_created, public_key: public_keys(:alice)).summary
    assert_equal "Clé « Bob » retirée du trousseau", Activity.record!(:public_key_deleted, public_key_name: "Bob").summary
    assert_equal "Clé Elio générée", Activity.record!(:ssh_key_generated, regenerated: false).summary
    assert_equal "Clé Elio régénérée", Activity.record!(:ssh_key_generated, regenerated: true).summary
    assert_equal "Scan des clés : 2/2", Activity.record!(:automation_run, automation_label: "Scan des clés", result: "2/2").summary
  end

  test "scopes" do
    old = travel_to(1.hour.ago) { Activity.record!(:server_created, server: servers(:web)) }
    added = Activity.record!(:key_added, server: servers(:web))
    detected = Activity.record!(:unknown_key_detected, server: servers(:web))

    assert_equal [ detected, added, old ], Activity.recent.to_a
    assert_equal [ added ], Activity.of_kind(:key_added).to_a
    assert_equal [ detected ], Activity.in_category(:security).to_a
    assert_equal [ old ], Activity.in_category("servers").to_a
  end

  test "server_deleted summary uses the copied name" do
    activity = Activity.record!(:server_deleted, server_name: "Web")
    assert_equal "Serveur « Web » supprimé d'Elio", activity.summary
    assert_equal :warning, activity.severity
  end
end
