require "application_system_test_case"

class ServerImportsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "previewing then importing servers from an ssh config" do
    visit servers_path
    fleet_action "Importer des serveurs"

    choose "~/.ssh/config"
    fill_in "Contenu", with: "Host api\n  HostName 10.0.0.12\n  User deploy\nHost web\n  HostName 10.0.0.99\n"
    click_on "Voir l'aperçu"

    assert_selector ".import-counts", text: "1 serveur à importer · 1 doublon ignoré · 0 ligne en erreur"
    click_on "Importer 1 serveur"

    assert_selector "#flash .toast", text: "1 serveur importé"
    assert_selector "#servers tbody tr", text: "api"
    assert_equal [ "10.0.0.12", 22, "deploy" ], Server.find_by!(name: "api").then { |server| [ server.host, server.port, server.username ] }
  end

  test "correcting a line in error in the preview, then importing without the inventory" do
    visit new_server_import_path
    fill_in "Contenu", with: "nom,hôte\nAPI,10.0.0.12\nDB,not a host!\n"
    click_on "Voir l'aperçu"

    assert_selector ".import-counts", text: "1 serveur à importer · 0 doublon ignoré · 1 ligne en erreur"
    within("tr.import-row.is-invalid") { find("input[aria-label='Hôte']").fill_in(with: "10.0.0.13") }
    click_on "Vérifier à nouveau"

    assert_selector ".import-counts", text: "2 serveurs à importer · 0 doublon ignoré · 0 ligne en erreur"
    uncheck "Lancer le premier inventaire des serveurs importés"
    click_on "Importer 2 serveurs"

    assert_selector "#flash .toast", text: "2 serveurs importés"
    assert_equal "10.0.0.13", Server.find_by!(name: "DB").host
  end
end
