require "application_system_test_case"

class IntegrationDataTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "deleting the data of a turned off extension, after a confirmation" do
    Integration.create!(kind: "uptime_kuma", last_synced_at: 2.days.ago, last_sync_duration_ms: 800)
    UptimeKumaMonitor.create!(monitor_id: "1", name: "web", server: servers(:web))

    visit edit_settings_integration_path("uptime_kuma")
    assert_text "Les données lues sur le service sont gardées pour une prochaine activation."
    find("#integration-actions summary").click
    accept_app_confirm { click_on "Supprimer les données" }

    assert_text "Données de l'extension Uptime Kuma supprimées."
    assert_no_selector "#integration-actions"
    assert_empty UptimeKumaMonitor.all
  end
end
