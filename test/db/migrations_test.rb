require "test_helper"
require Rails.root.join("db/migrate/20261106080000_refresh_health_reasons_after_upgrade")

class MigrationsTest < ActiveSupport::TestCase
  test "the health reasons of an older version are stored again as translation keys" do
    server = servers(:web)
    server.update_columns(ssh_ok: false, health_reasons: [ { "tone" => "crit", "text" => "Clé d'Elio refusée" } ])

    ActiveRecord::Migration.suppress_messages { RefreshHealthReasonsAfterUpgrade.new.up }

    assert_includes server.reload.health_reasons, { "tone" => "crit", "key" => "health.key_refused", "params" => {} }
    assert server.health_reasons.none? { |reason| reason.key?("text") }
  end
end
